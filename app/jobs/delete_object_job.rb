class DeleteObjectJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 5_000

  def perform(object, user = nil, ip = nil)
    # Pre-purge heavy associations for large objects to avoid
    # timeouts & race conditions due to destroy_async fan-out.
    purge_heavy_associations(object)
    object.destroy!
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  def heavy_associations
    # UniverZAP additions (ai_assistants, funnels, kanban_tasks) declare
    # `dependent: :destroy_async` on Account so their FK rows survive
    # past the parent `destroy!` call and trigger PG foreign-key
    # violations. Pre-purging them synchronously here matches how the
    # legacy heavy children (conversations, contacts, inboxes,
    # reporting_events) are handled.
    {
      Account => %i[conversations contacts inboxes reporting_events ai_assistants funnels kanban_tasks],
      Inbox => %i[conversations contact_inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    heavy_associations[klass].each do |assoc|
      next unless object.respond_to?(assoc)

      batch_destroy(object.public_send(assoc))
    end
  end

  def batch_destroy(relation)
    relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each(&:destroy!)
    end
  end
end

DeleteObjectJob.prepend_mod_with('DeleteObjectJob')
