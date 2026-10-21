# Pastas que organizam as campanhas de status. Só administrador, como o resto
# de "Meu WhatsApp".
class Api::V1::Accounts::Whatsapp::StatusFoldersController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator
  before_action :fetch_folder, only: [:update, :destroy]

  def index
    counts = Current.account.whatsapp_status_campaigns.group(:folder_id).count
    folders = Current.account.whatsapp_status_folders.order(:name)
    render json: {
      payload: folders.map { |folder| payload(folder, counts[folder.id]) },
      meta: { unfiled_count: counts[nil].to_i, total_count: counts.values.sum }
    }
  end

  def create
    render json: payload(Current.account.whatsapp_status_folders.create!(folder_params))
  end

  def update
    @folder.update!(folder_params)
    render json: payload(@folder)
  end

  # As campanhas da pasta continuam existindo, só ficam "Sem pasta".
  def destroy
    @folder.destroy!
    head :ok
  end

  private

  def ensure_administrator
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_folder
    @folder = Current.account.whatsapp_status_folders.find(params[:id])
  end

  def folder_params
    params.permit(:name, :color)
  end

  def payload(folder, count = nil)
    folder.slice(:id, :name, :color).merge(campaigns_count: count || folder.campaigns.count)
  end
end
