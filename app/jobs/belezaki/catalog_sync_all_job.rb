# One catalogue sync per account with the belezaki app connected, daily.
class Belezaki::CatalogSyncAllJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Integrations::Hook.enabled.where(app_id: Belezaki::TenantResolver::APP_ID).find_each do |hook|
      Belezaki::CatalogSyncJob.perform_later(hook.account_id)
    end
  end
end
