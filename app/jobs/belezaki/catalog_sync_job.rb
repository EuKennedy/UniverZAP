# Pulls the salon catalogue fresh and syncs it into the account's attributes.
# Runs once the app is connected and every morning (Belezaki::CatalogSyncAllJob).
class Belezaki::CatalogSyncJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find(account_id)
    catalog = Belezaki::CatalogService.new(account: account, refresh: true).perform
    Belezaki::CatalogSyncService.new(account: account, catalog: catalog).perform
  end
end
