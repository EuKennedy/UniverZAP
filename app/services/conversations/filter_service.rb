class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :messages, :contact_inbox,
      :kanban_tasks
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page)
  end

  # UniverZAP: a conversation can be linked to several tasks, so it matches when
  # any of them sits in one of the stages. EXISTS keeps it from repeating.
  def kanban_stage_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = query_hash['values'].map(&:to_i)
    'EXISTS (SELECT 1 FROM kanban_task_conversations ktc INNER JOIN kanban_tasks kt ON kt.id = ktc.kanban_task_id ' \
      "WHERE ktc.conversation_id = conversations.id AND kt.funnel_stage_id IN (:value_#{current_index})) #{query_hash[:query_operator]}"
  end

  # UniverZAP: a day is the agent's day, not UTC's. The dashboard sends its IANA
  # timezone; without it, "today" in Brazil would end at 21:00.
  def date_filter(current_filter, query_hash, filter_operator_value)
    zone = ActiveSupport::TimeZone[@params[:timezone].to_s]
    return super unless zone

    timezone = ActiveRecord::Base.connection.quote(zone.tzinfo.name)
    "(#{filter_config[:table_name]}.#{query_hash[:attribute_key]} AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})::#{current_filter['data_type']} " \
      "#{filter_operator_value} #{query_hash[:query_operator]}"
  end
end
