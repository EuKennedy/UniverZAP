class Api::V1::Accounts::Integrations::BelezakiController < Api::V1::Accounts::BaseController
  # The salon's card for one contact of the account. Any agent may read it: it
  # is what the sidebar shows next to the conversation they are answering.
  def customer
    contact = Current.account.contacts.find(params[:contact_id])
    render json: Belezaki::CustomerCardService.new(account: Current.account, contact: contact).perform
  end
end
