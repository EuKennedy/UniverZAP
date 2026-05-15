class Kanban::AutomationService
  CLOSED_STAGE_STATUSES = %w[won lost].freeze

  class << self
    def handle_conversation_created(conversation)
      return if conversation.blank? || conversation.inbox_id.blank?

      eligible_funnels_for_inbox(conversation).find_each do |funnel|
        next unless funnel.automation_enabled?('auto_create_task_for_new_conversation')
        next if task_for_conversation_exists?(funnel, conversation)

        stage = funnel.funnel_stages.ordered.first
        next if stage.blank?

        create_task_for_conversation(funnel, stage, conversation)
      end
    end

    def handle_conversation_resolved(conversation)
      conversation.kanban_tasks.includes(:funnel, :funnel_stage).find_each do |task|
        funnel = task.funnel
        next unless funnel.automation_enabled?('auto_win_task_on_conversation_resolve')
        next if task.funnel_stage&.status_type.to_s == 'lost'

        won_stage = funnel.funnel_stages.where(status_type: FunnelStage.status_types[:won]).order(:position).first
        next if won_stage.blank? || task.funnel_stage_id == won_stage.id

        task.update(funnel_stage: won_stage)
      end
    end

    def handle_assignee_changed(conversation)
      return if conversation.assignee_id.blank?

      conversation.kanban_tasks.includes(:funnel).find_each do |task|
        next unless task.funnel.automation_enabled?('sync_task_conversation_assignees')
        next if task.assignee_ids == [conversation.assignee_id]

        task.assignee_ids = [conversation.assignee_id]
      end
    end

    def handle_task_stage_changed(task)
      return unless task.funnel.automation_enabled?('auto_resolve_conversation_on_task_close')
      return unless CLOSED_STAGE_STATUSES.include?(task.funnel_stage&.status_type.to_s)

      task.conversations.where.not(status: Conversation.statuses[:resolved]).find_each do |conversation|
        conversation.update(status: :resolved)
      end
    end

    def handle_task_assignees_changed(task)
      return unless task.funnel.automation_enabled?('sync_task_conversation_assignees')

      primary_assignee_id = task.assignee_ids.first
      return if primary_assignee_id.blank?

      task.conversations.where.not(assignee_id: primary_assignee_id).find_each do |conversation|
        conversation.update(assignee_id: primary_assignee_id)
      end
    end

    def handle_task_created(task)
      return unless task.funnel.automation_enabled?('auto_assign_task_to_agent')
      return if task.assignee_ids.any?

      assignee_id = task.conversations.where.not(assignee_id: nil).pick(:assignee_id)
      return if assignee_id.blank?

      task.assignee_ids = [assignee_id]
    end

    private

    def eligible_funnels_for_inbox(conversation)
      Funnel.joins(:funnel_inboxes)
            .where(account_id: conversation.account_id, funnel_inboxes: { inbox_id: conversation.inbox_id })
    end

    def task_for_conversation_exists?(funnel, conversation)
      funnel.kanban_tasks
            .joins(:kanban_task_conversations)
            .where(kanban_task_conversations: { conversation_id: conversation.id })
            .exists?
    end

    def create_task_for_conversation(funnel, stage, conversation)
      KanbanTask.transaction do
        task = funnel.kanban_tasks.create!(
          account: funnel.account,
          funnel_stage: stage,
          title: build_task_title(conversation),
          priority: build_task_priority(conversation)
        )
        task.conversations << conversation
        task.contacts << conversation.contact if conversation.contact && task.contact_ids.exclude?(conversation.contact_id)

        if funnel.automation_enabled?('auto_assign_task_to_agent') && conversation.assignee_id.present?
          task.assignee_ids = [conversation.assignee_id]
        end
      end
    end

    def build_task_title(conversation)
      contact_name = conversation.contact&.name.presence
      return "Conversation ##{conversation.display_id}" if contact_name.blank?

      "#{contact_name} (##{conversation.display_id})"
    end

    def build_task_priority(conversation)
      return 'none' if conversation.priority.blank?

      conversation.priority.to_s
    end
  end
end
