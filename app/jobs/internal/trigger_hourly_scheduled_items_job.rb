class Internal::TriggerHourlyScheduledItemsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Whatsapp::WahaHistoryReconcileJob.perform_later
  end
end

Internal::TriggerHourlyScheduledItemsJob.prepend_mod_with('Internal::TriggerHourlyScheduledItemsJob')
