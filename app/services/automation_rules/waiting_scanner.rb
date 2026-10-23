# The time-based trigger: "the customer has been waiting for an agent for
# more than X minutes". Nothing fires an event when nothing happens, so a cron
# sweep looks every few minutes at conversations where the customer has the
# last word (awaiting_reply, the same field as the risk queue) and no human
# answered since (waiting_since), and runs
#   - every active `conversation_waiting` automation rule whose threshold has
#     passed, once per waiting period (AutomationRuleFiring);
#   - every live chatflow with the `no_reply` trigger, once per waiting period
#     (an execution created since waiting_since counts as done).
#
# The same sweep runs the `conversation_unresolved` rules (resolution SLA):
# conversations still open for more than X minutes since they were created,
# once per conversation.
class AutomationRules::WaitingScanner
  BATCH_LIMIT = 500

  # event => [threshold condition key, scope builder, dedupe key]
  SWEEPS = {
    'conversation_waiting' => ['waiting_minutes', :waiting_conversations, ->(c) { c.waiting_since.to_i.to_s }],
    'conversation_unresolved' => ['open_minutes', :unresolved_conversations, ->(c) { c.created_at.to_i.to_s }]
  }.freeze

  def perform
    SWEEPS.each_key do |event|
      AutomationRule.active.joins(:account).where(event_name: event).find_each { |rule| run_rule(rule) }
    end
    Chatflow.live.joins(:account).trigger_no_reply.find_each { |chatflow| run_chatflow(chatflow) }
  end

  private

  def run_rule(rule)
    threshold_key, scope_builder, dedupe = SWEEPS.fetch(rule.event_name)
    minutes = threshold_minutes(rule, threshold_key)
    return if minutes.nil?

    send(scope_builder, rule.account.conversations, minutes).each do |conversation|
      key = dedupe.call(conversation)
      next if AutomationRuleFiring.exists?(automation_rule: rule, conversation: conversation, dedupe_key: key)
      next unless AutomationRules::ConditionsFilterService.new(rule, conversation, {}).perform

      AutomationRuleFiring.create!(automation_rule: rule, conversation: conversation, dedupe_key: key)
      AutomationRules::ActionService.new(rule, rule.account, conversation).perform
    end
  end

  # The rule's own "more than N minutes" condition is the sweep's threshold.
  # A rule without one would fire on every conversation every five minutes,
  # so it is skipped rather than guessed.
  def threshold_minutes(rule, threshold_key)
    rule.conditions
        .select { |c| c['attribute_key'] == threshold_key && c['filter_operator'] == 'is_greater_than' }
        .filter_map { |c| Array(c['values']).first&.to_i }
        .min
  end

  def unresolved_conversations(scope, minutes)
    scope.open.where(created_at: ..minutes.minutes.ago).order(:created_at).limit(BATCH_LIMIT)
  end

  def waiting_conversations(scope, minutes)
    scope.open.where(awaiting_reply: true)
         .where.not(waiting_since: nil)
         .where(waiting_since: ..minutes.minutes.ago)
         .order(:waiting_since).limit(BATCH_LIMIT)
  end

  def run_chatflow(chatflow)
    scope = chatflow.inbox_id ? chatflow.account.conversations.where(inbox_id: chatflow.inbox_id) : chatflow.account.conversations
    waiting_conversations(scope, chatflow.no_reply_minutes).each do |conversation|
      next if chatflow.executions.where(conversation_id: conversation.id).exists?(created_at: conversation.waiting_since..)

      Chatflow::EngineService.force_start(chatflow, conversation)
    end
  end
end
