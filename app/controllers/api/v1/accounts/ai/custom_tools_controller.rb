class Api::V1::Accounts::Ai::CustomToolsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_tool, only: [:update, :destroy]

  def index
    render json: { payload: @assistant.custom_tools.order(:id).map(&:push_event_data) }
  end

  def create
    tool = @assistant.custom_tools.create!(permitted_params.merge(account: Current.account))
    render json: tool.push_event_data
  end

  def update
    @tool.update!(permitted_params)
    render json: @tool.push_event_data
  end

  def destroy
    @tool.destroy!
    head :ok
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  # Scoped to the current account's agents — a workspace can only ever configure
  # its own agents' integrations.
  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def fetch_tool
    @tool = @assistant.custom_tools.find(params[:id])
  end

  def permitted_params
    params.require(:ai_custom_tool).permit(
      :title, :description, :endpoint_url, :http_method, :auth_type, :enabled,
      :request_template, :response_template,
      auth_config: {}, param_schema: [:name, :type, :description, :required]
    )
  end
end
