class ConversationFinder
  attr_reader :current_user, :current_account, :params

  DEFAULT_STATUS = 'open'.freeze
  SORT_OPTIONS = {
    'last_activity_at_asc' => %w[sort_on_last_activity_at asc],
    'last_activity_at_desc' => %w[sort_on_last_activity_at desc],
    'created_at_asc' => %w[sort_on_created_at asc],
    'created_at_desc' => %w[sort_on_created_at desc],
    'priority_asc' => %w[sort_on_priority asc],
    'priority_desc' => %w[sort_on_priority desc],
    'waiting_since_asc' => %w[sort_on_waiting_since asc],
    'waiting_since_desc' => %w[sort_on_waiting_since desc],
    'priority_desc_created_at_asc' => %w[sort_on_priority_created_at desc],

    # To be removed in v3.5.0
    'latest' => %w[sort_on_last_activity_at desc],
    'sort_on_created_at' => %w[sort_on_created_at asc],
    'sort_on_priority' => %w[sort_on_priority desc],
    'sort_on_waiting_since' => %w[sort_on_waiting_since asc]
  }.with_indifferent_access
  # assumptions
  # inbox_id if not given, take from all conversations, else specific to inbox
  # assignee_type if not given, take 'all'
  # conversation_status if not given, take 'open'

  # response of this class will be of type
  # {conversations: [array of conversations], count: {open: count, resolved: count}}

  # params
  # assignee_type, inbox_id, :status

  def initialize(current_user, params)
    @current_user = current_user
    @current_account = current_user.account
    @is_admin = current_account.account_users.find_by(user_id: current_user.id)&.administrator?
    @params = params
  end

  def perform
    set_up

    # Counters MUST be computed before conversation_type/assignee_type filters
    # so every tab badge reflects the same base set. Otherwise switching tabs
    # zeroes out the counter of the other tab.
    counts = build_count_payload

    apply_group_scope
    filter_by_conversation_type if params[:conversation_type]
    filter_by_attendance_state
    filter_by_assignee_type
    filter_by_created_on

    { conversations: conversations, count: counts }
  end

  # UniverZAP: the agenda strip of the list — how many conversations of the
  # current view started on each day between params[:from] and params[:to],
  # days in the agent's timezone. Same scope as #perform, minus the day.
  def perform_created_per_day
    set_up
    apply_group_scope
    filter_by_conversation_type if params[:conversation_type]
    filter_by_attendance_state
    filter_by_assignee_type

    range = time_zone.parse(params[:from]).beginning_of_day..time_zone.parse(params[:to]).end_of_day
    @conversations.where(created_at: range).group(local_created_day).count.transform_keys(&:iso8601)
  end

  def perform_meta_only
    set_up
    { count: build_count_payload }
  end

  # UniverZAP: WhatsApp groups, the contacts' statuses and the team live only
  # in their own tabs (conversation_type=groups / status / team); the regular
  # tabs exclude all three. Applied after the badge counts are computed.
  def apply_group_scope
    @conversations = case params[:conversation_type]
                     when 'groups' then @conversations.groups
                     when 'status' then @conversations.status_broadcasts
                     when 'team' then @conversations.team_chats
                     else @conversations.regular
                     end
  end

  private

  def set_up
    set_inboxes
    set_team
    set_assignee_type

    find_all_conversations
    # Snapshot before the status filter narrows @conversations: resolved_count
    # needs every status, not just whichever one the active tab asked for.
    @conversations_before_status = @conversations
    filter_by_status unless params[:q]
    filter_by_team
    filter_by_labels
    filter_by_query
    filter_by_source_id
  end

  def set_inboxes
    @inbox_ids = if params[:inbox_id]
                   @current_user.assigned_inboxes.where(id: params[:inbox_id])
                 else
                   @current_user.assigned_inboxes.pluck(:id)
                 end
  end

  def set_assignee_type
    @assignee_type = params[:assignee_type]
  end

  def set_team
    @team = current_account.teams.find(params[:team_id]) if params[:team_id]
  end

  def find_conversation_by_inbox
    # `not_sandbox` keeps the Athenas test-playground transcript out of every
    # conversation list: it is a real conversation on purpose (so the agent runs
    # the production path) but it is not a customer.
    @conversations = current_account.conversations.not_sandbox

    return unless params[:inbox_id]

    @conversations = @conversations.where(inbox_id: @inbox_ids)
  end

  def find_all_conversations
    find_conversation_by_inbox
    # Apply permission-based filtering
    @conversations = Conversations::PermissionFilterService.new(
      @conversations,
      current_user,
      current_account
    ).perform
    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = @conversations.unassigned
    when 'assigned'
      @conversations = @conversations.assigned
    end
    @conversations
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      conversation_ids = current_account.mentions.where(user: current_user).pluck(:conversation_id)
      @conversations = @conversations.where(id: conversation_ids)
    when 'participating'
      @conversations = current_user.participating_conversations.where(account_id: current_account.id)
    when 'unattended'
      @conversations = @conversations.unattended
    end
    @conversations
  end

  # UniverZAP: whose turn it is, in the Todos dropdown — Aguardando (ours),
  # Aguardando cliente (theirs); Em atendimento (in_attendance) is both, so it
  # narrows nothing. A param of its own, so it narrows any conversation_type
  # (mentions, unattended…) instead of replacing it. These are queues of work
  # still going on: a resolved conversation never sits in one, whatever status
  # filter the agent has saved, until a message from the contact reopens it.
  def filter_by_attendance_state
    case params[:attendance_state]
    when 'waiting' then @conversations = in_queue.waiting
    when 'awaiting_customer' then @conversations = in_queue.awaiting_customer
    when 'in_attendance' then @conversations = in_queue
    # UniverZAP: the two halves of the resolved list — Agendadas (customer
    # won, carries the vertical's scheduling status; see
    # Conversations::ScheduleService) and the plain Resolvidas without it.
    # A vertical that doesn't schedule has no such split.
    when 'scheduled', 'resolved' then split_resolved_by_schedule
    end
  end

  def in_queue
    @conversations.where.not(status: :resolved)
  end

  def split_resolved_by_schedule
    return unless schedule_status

    @conversations = @conversations.tagged_with(schedule_status, on: :labels, exclude: params[:attendance_state] == 'resolved')
  end

  def schedule_status
    VerticalProfile.for(current_account).schedule_status
  end

  # UniverZAP: only the conversations that started on params[:created_on]
  # (YYYY-MM-DD in the agent's timezone). Narrows the list, never the badges.
  def filter_by_created_on
    return if params[:created_on].blank?

    @conversations = @conversations.where(created_at: time_zone.parse(params[:created_on]).all_day)
  end

  def time_zone
    @time_zone ||= ActiveSupport::TimeZone[params[:timezone].to_s] || Time.zone
  end

  def local_created_day
    zone = Conversation.connection.quote(time_zone.tzinfo.name)
    Arel.sql("date(conversations.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{zone})")
  end

  def filter_by_query
    return unless params[:q]

    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    @conversations = conversations.joins(:messages).where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types }).includes(:messages)
                                  .where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types })
  end

  def filter_by_status
    return if params[:status] == 'all'

    @conversations = @conversations.where(status: params[:status] || DEFAULT_STATUS)
  end

  def filter_by_team
    return unless @team

    @conversations = @conversations.where(team: @team)
  end

  def filter_by_labels
    return unless params[:labels]

    @conversations = @conversations.tagged_with(params[:labels], any: true)
  end

  def filter_by_source_id
    return unless params[:source_id]

    @conversations = @conversations.joins(:contact_inbox)
    @conversations = @conversations.where(contact_inboxes: { source_id: params[:source_id] })
  end

  # Standard tab badges (Todos/Minhas/Aguardando/Em atendimento) always count
  # OPEN conversations, no matter which status the active view asked for —
  # otherwise picking Resolvidas would also narrow every other badge to
  # resolved conversations. Built from the pre-status snapshot, so it never
  # inherits whatever params[:status] the current request carries.
  def count_scope
    @conversations_before_status.regular.where(status: 'open')
  end

  def set_count_for_all_conversations
    [
      count_scope.assigned_to(current_user).count,
      count_scope.unassigned.count,
      count_scope.count
    ]
  end

  def build_count_payload
    mine_count, unassigned_count, all_count = set_count_for_all_conversations
    {
      mine_count: mine_count,
      assigned_count: all_count - unassigned_count,
      unassigned_count: unassigned_count,
      all_count: all_count,
      **resolution_counts,
      group_count: @conversations_before_status.groups.count,
      status_count: @conversations_before_status.status_broadcasts.count,
      team_count: @conversations_before_status.team_chats.where(status: 'open').count,
      **attendance_state_counts(all_count)
    }
  end

  # UniverZAP: badges of Resolvidas and Agendadas — the resolved conversations
  # split by the scheduling status, so a customer won never counts as a plain
  # resolve.
  def resolution_counts
    resolved = @conversations_before_status.regular.where(status: 'resolved')
    scheduled = schedule_status ? resolved.tagged_with(schedule_status, on: :labels).count : 0
    { resolved_count: resolved.count - scheduled, scheduled_count: scheduled }
  end

  # UniverZAP: badges of the turn views. One query: every regular open
  # conversation is either ours or theirs, and Em atendimento is both.
  def attendance_state_counts(all_count)
    waiting_count = count_scope.waiting.count
    { waiting_count: waiting_count, awaiting_customer_count: all_count - waiting_count, in_attendance_count: all_count }
  end

  def current_page
    params[:page] || 1
  end

  def conversations_base_query
    @conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :contact_inbox,
      :kanban_tasks
    )
  end

  def conversations
    @conversations = conversations_base_query

    sort_by, sort_order = SORT_OPTIONS[params[:sort_by]] || SORT_OPTIONS['last_activity_at_desc']
    @conversations = @conversations.send(sort_by, sort_order)

    if params[:updated_within].present?
      @conversations.where('conversations.updated_at > ?', Time.zone.now - params[:updated_within].to_i.seconds)
    else
      @conversations.page(current_page).per(ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25').to_i)
    end
  end
end
ConversationFinder.prepend_mod_with('ConversationFinder')
