# Single entry point for emitting kanban events to subscribed external
# URLs. Models call `Kanban::WebhookDispatcher.dispatch('task.created', task)`
# and we fan out to every matching `KanbanWebhookSubscription` on the
# account, queuing a delivery job per subscriber so HTTP latency never
# blocks the source request.
class Kanban::WebhookDispatcher
  def self.dispatch(event, resource)
    return if resource.blank? || resource.account_id.blank?
    return unless KanbanWebhookSubscription::EVENTS.include?(event.to_s)

    payload = build_payload(event, resource)
    subscriptions = KanbanWebhookSubscription.for_event(
      account_id: resource.account_id,
      event: event.to_s
    )
    subscriptions.find_each do |subscription|
      Kanban::WebhookSubscriptionDeliveryJob.perform_later(subscription.id, event.to_s, payload)
    end
  end

  def self.build_payload(event, resource)
    {
      event: event.to_s,
      delivered_at: Time.current.iso8601,
      account_id: resource.account_id,
      data: resource.respond_to?(:push_event_data) ? resource.push_event_data : { id: resource.id }
    }
  end
end
