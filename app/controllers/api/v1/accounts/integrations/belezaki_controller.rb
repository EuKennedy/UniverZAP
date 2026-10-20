class Api::V1::Accounts::Integrations::BelezakiController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, only: [:sync_catalog]

  # The salon's card for one contact of the account. Any agent may read it: it
  # is what the sidebar shows next to the conversation they are answering.
  def customer
    contact = Current.account.contacts.find(params[:contact_id])
    render json: Belezaki::CustomerCardService.new(account: Current.account, contact: contact).perform
  end

  # Services and professionals, for the catalogue block and the Apps page.
  def catalog
    render json: Belezaki::CatalogService.new(account: Current.account).perform
  end

  # Fresh pull plus the attribute sync, on demand from the Apps page.
  def sync_catalog
    catalog = Belezaki::CatalogService.new(account: Current.account, refresh: true).perform
    sync = Belezaki::CatalogSyncService.new(account: Current.account, catalog: catalog).perform
    render json: catalog.merge(sync: sync)
  end
end
