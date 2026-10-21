# UniverZAP: who is in the Equipe tab. Everyone sees the team; only admins
# change it.
class Api::V1::Accounts::TeamContactsController < Api::V1::Accounts::BaseController
  before_action :authorize_change, only: [:create, :destroy]

  def index
    render json: { payload: team.map { |contact| contact_json(contact) } }
  end

  def create
    contact = Current.account.contacts.find(params[:contact_id])
    render json: contact_json(Contacts::TeamService.new(contact).add)
  end

  def destroy
    contact = Current.account.contacts.find(params[:id])
    Contacts::TeamService.new(contact).remove
    head :no_content
  end

  private

  def team
    Current.account.contacts
           .where("contacts.custom_attributes ->> ? = 'true'", Contacts::TeamService::ATTRIBUTE)
           .order(:name)
  end

  def contact_json(contact)
    { id: contact.id, name: contact.name, phone_number: contact.phone_number, thumbnail: contact.avatar_url }
  end

  def authorize_change
    authorize Current.account, :update?
  end
end
