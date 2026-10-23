class AutomationRuleListener < BaseListener
  def conversation_updated(event)
    return if sandbox_event?(event)

    process_conversation_event(event, 'conversation_updated')
    process_label_added_event(event)
  end

  def conversation_created(event)
    return if sandbox_event?(event)

    process_conversation_event(event, 'conversation_created')
  end

  def conversation_opened(event)
    return if sandbox_event?(event)

    process_conversation_event(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    return if sandbox_event?(event)

    process_conversation_event(event, 'conversation_resolved')
  end

  # UniverZAP: fired once per conversation by Conversations::AdReferralService
  # when its first message came from a Click-to-WhatsApp ad.
  def conversation_ad_referral(event)
    return if sandbox_event?(event)

    process_conversation_event(event, 'conversation_ad_referral')
  end

  # UniverZAP: fired once per conversation by Conversations::RecurringCustomerService
  # when the contact already had a conversation that ended.
  def conversation_recurring_customer(event)
    return if sandbox_event?(event)

    process_conversation_event(event, 'conversation_recurring_customer')
  end

  def message_created(event)
    return if sandbox_event?(event)

    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    changed_attributes = event.data[:changed_attributes]

    return unless rule_present?('message_created', account)

    rules = current_account_rules('message_created', account)

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, message.conversation,
                                                                        { message: message, changed_attributes: changed_attributes }).perform
      ::AutomationRules::ActionService.new(rule, account, message.conversation).perform if conditions_match.present?
    end
  end

  private

  # UniverZAP: "label/status X was just applied" — runs the
  # conversation_label_added rules against the labels this update added.
  def process_label_added_event(event)
    return if performed_by_automation?(event)

    conversation = event.data[:conversation]
    previous, current = event.data[:changed_attributes].to_h.with_indifferent_access[:label_list]
    added = Array(current) - Array(previous)
    return if added.empty?

    account = conversation.account
    return unless rule_present?('conversation_label_added', account)

    current_account_rules('conversation_label_added', account).each do |rule|
      next unless AutomationRules::LabelAddedMatcher.new(rule, conversation, added).match?

      AutomationRules::ActionService.new(rule, account, conversation).perform
    end
  end

  def process_conversation_event(event, event_name)
    return if performed_by_automation?(event)

    auto_reply_skip_events = %w[conversation_created conversation_opened]
    return if auto_reply_skip_events.include?(event_name) && ignore_auto_reply_event?(event)

    conversation = event.data[:conversation]
    account = conversation.account
    changed_attributes = event.data[:changed_attributes]

    return unless rule_present?(event_name, account)

    rules = current_account_rules(event_name, account)

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, { changed_attributes: changed_attributes }).perform
      AutomationRules::ActionService.new(rule, account, conversation).perform if conditions_match.present?
    end
  end

  def rule_present?(event_name, account)
    return if account.blank?

    current_account_rules(event_name, account).any?
  end

  def current_account_rules(event_name, account)
    AutomationRule.where(
      event_name: event_name,
      account_id: account.id,
      active: true
    )
  end

  def performed_by_automation?(event)
    event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
  end

  def ignore_auto_reply_event?(event)
    conversation = event.data[:conversation]
    conversation.additional_attributes['auto_reply'].present?
  end

  def ignore_message_created_event?(event)
    message = event.data[:message]
    performed_by_automation?(event) || message.activity? || message.auto_reply_email?
  end
end
