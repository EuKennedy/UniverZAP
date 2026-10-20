# Modelos de status reutilizáveis ("agenda aberta", "promoção de terça").
# Só administrador, como o resto de "Meu WhatsApp".
class Api::V1::Accounts::Whatsapp::StatusTemplatesController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator
  before_action :fetch_template, only: [:update, :destroy]

  def index
    render json: { payload: Current.account.whatsapp_status_templates.order(:name).map { |template| payload(template) } }
  end

  def create
    template = Current.account.whatsapp_status_templates.create!(template_params)
    render json: payload(template)
  end

  def update
    @template.update!(template_params)
    render json: payload(@template)
  end

  def destroy
    @template.destroy!
    head :ok
  end

  private

  def ensure_administrator
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_template
    @template = Current.account.whatsapp_status_templates.find(params[:id])
  end

  def template_params
    params.permit(:name, :body, :background_color, :font)
  end

  def payload(template)
    template.slice(:id, :name, :body, :background_color, :font)
  end
end
