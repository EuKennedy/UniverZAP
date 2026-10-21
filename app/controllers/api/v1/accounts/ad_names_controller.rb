# UniverZAP: the name of a Click-to-WhatsApp ad. WhatsApp only hands over the
# ad id (its "title" is api.whatsapp.com), so the Painel shows whatever name
# the account gave the ad — typed by an admin or copied from Ads Manager —
# kept in account.custom_attributes['ad_names'] as { ad_id => { name, campaign } }.
class Api::V1::Accounts::AdNamesController < Api::V1::Accounts::BaseController
  before_action { authorize Current.account, :update? }

  def update
    names = (account.custom_attributes['ad_names'] || {}).dup
    entry.empty? ? names.delete(params[:id]) : names[params[:id]] = entry
    account.update!(custom_attributes: account.custom_attributes.merge('ad_names' => names))
    render json: { ad_id: params[:id], **entry.symbolize_keys }
  end

  private

  def account
    Current.account
  end

  def entry
    @entry ||= { 'name' => params[:name].to_s.strip.presence, 'campaign' => params[:campaign].to_s.strip.presence }.compact
  end
end
