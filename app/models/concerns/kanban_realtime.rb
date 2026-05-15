module KanbanRealtime
  extend ActiveSupport::Concern

  included do
    after_create_commit  :broadcast_kanban_created
    after_update_commit  :broadcast_kanban_updated
    after_destroy_commit :broadcast_kanban_destroyed
  end

  private

  def broadcast_kanban_created
    broadcast_kanban_event("#{kanban_event_prefix}.created")
  end

  def broadcast_kanban_updated
    broadcast_kanban_event("#{kanban_event_prefix}.updated")
  end

  def broadcast_kanban_destroyed
    broadcast_kanban_event("#{kanban_event_prefix}.deleted", kanban_destroyed_payload)
  end

  def broadcast_kanban_event(event_name, payload = nil)
    target_account = kanban_account
    return if target_account.blank?

    ActionCableBroadcastJob.perform_later(
      ["account_#{target_account.id}"],
      event_name,
      (payload || kanban_event_payload).merge(account_id: target_account.id)
    )
  end

  def kanban_event_prefix
    self.class.name.underscore.tr('/', '_')
  end

  def kanban_event_payload
    raise NotImplementedError, "#{self.class.name} must implement #kanban_event_payload"
  end

  def kanban_destroyed_payload
    { id: id, funnel_id: try(:funnel_id) }.compact
  end

  def kanban_account
    return account if respond_to?(:account) && account.present?

    funnel&.account
  end
end
