class ActionService
  include EmailHelper

  def initialize(conversation)
    @conversation = conversation.reload
    @account = @conversation.account
  end

  def mute_conversation(_params)
    @conversation.mute!
  end

  def snooze_conversation(_params)
    @conversation.snoozed!
  end

  def resolve_conversation(_params)
    @conversation.resolved!
  end

  def open_conversation(_params)
    @conversation.open!
  end

  def pending_conversation(_params)
    @conversation.pending!
  end

  def change_status(status)
    @conversation.update!(status: status[0])
  end

  def change_priority(priority)
    @conversation.update!(priority: (priority[0] == 'nil' ? nil : priority[0]))
  end

  def add_label(labels)
    return if labels.empty?

    @conversation.reload.add_labels(labels)
  end

  def assign_agent(agent_ids = [])
    return @conversation.update!(assignee_id: nil) if agent_ids[0] == 'nil'

    agent_ids = [last_responding_agent_id] if agent_ids[0] == 'last_responding_agent'
    return unless agent_belongs_to_inbox?(agent_ids)

    @agent = @account.users.find_by(id: agent_ids)
    return unless @agent.present? && @agent.confirmed?

    @conversation.update!(assignee_id: @agent.id)
  end

  def remove_label(labels)
    return if labels.empty?

    labels = @conversation.label_list - labels
    @conversation.update(label_list: labels)
  end

  def assign_team(team_ids = [])
    # Keep nil/0 handling for existing automation and macro payloads.
    should_unassign = team_ids.blank? || %w[nil 0].include?(team_ids[0].to_s)
    return @conversation.update!(team_id: nil) if should_unassign

    # check if team belongs to account only if team_id is present
    # if team_id is nil, then it means that the team is being unassigned
    return unless !team_ids[0].nil? && team_belongs_to_account?(team_ids)

    @conversation.update!(team_id: team_ids[0])
  end

  def remove_assigned_agent(_params)
    @conversation.update!(assignee_id: nil)
  end

  def remove_assigned_team(_params)
    @conversation.update!(team_id: nil)
  end

  def send_email_transcript(emails)
    return unless @account.email_transcript_enabled?

    emails = emails[0].gsub(/\s+/, '').split(',')

    emails.each do |email|
      break unless @account.within_email_rate_limit?

      email = parse_email_variables(@conversation, email)
      ConversationReplyMailer.with(account: @conversation.account).conversation_transcript(@conversation, email)&.deliver_later
      @account.increment_email_sent_count
    end
  end

  # UniverZAP: hand the conversation to whoever the inbox policy picks (least
  # busy / round robin), never back to the agent who is not answering.
  def assign_least_busy(_params)
    AutoAssignment::AssignmentService.new(inbox: @conversation.inbox).reassign(@conversation)
  end

  # UniverZAP: a private note that @mentions the team, so every member gets
  # the mention notification (push/e-mail) without a new notification type.
  def notify_team(params)
    teams = @account.teams.where(id: params[0][:team_ids])
    return if teams.empty?

    mentions = teams.map { |team| "[@#{team.name}](mention://team/#{team.id}/#{team.name})" }.join(' ')
    content = [mentions, params[0][:message].to_s].reject(&:blank?).join(' ')
    Messages::MessageBuilder.new(nil, @conversation, { content: content, private: true,
                                                       content_attributes: { automation_rule_id: Current.executed_by&.id } }).perform
  end

  # UniverZAP: start a Chatflow on the conversation (e.g. a rescue message).
  def start_chatflow(chatflow_ids)
    chatflow = @account.chatflows.find_by(id: chatflow_ids[0])
    Chatflow::EngineService.force_start(chatflow, @conversation) if chatflow
  end

  private

  def last_responding_agent_id
    @conversation.messages.outgoing.where(sender_type: 'User', private: false).last&.sender_id
  end

  def agent_belongs_to_inbox?(agent_ids)
    member_ids = @conversation.inbox.members.pluck(:user_id)
    assignable_agent_ids = member_ids + @account.administrators.ids

    assignable_agent_ids.include?(agent_ids[0])
  end

  def team_belongs_to_account?(team_ids)
    @account.team_ids.include?(team_ids[0])
  end

  def conversation_a_tweet?
    return false if @conversation.additional_attributes.blank?

    @conversation.additional_attributes['type'] == 'tweet'
  end
end

ActionService.include_mod_with('ActionService')
