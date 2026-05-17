class Api::V1::Accounts::Ai::IntentsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_intent, only: [:update, :destroy]

  def index
    @intents = @assistant.intents.order(:position, :id)
    render json: { payload: @intents.map(&:push_event_data) }
  end

  def create
    @intent = @assistant.intents.create!(permitted_params.merge(account: Current.account))
    render json: @intent.push_event_data
  end

  def update
    @intent.update!(permitted_params)
    render json: @intent.push_event_data
  end

  def destroy
    @intent.destroy!
    head :ok
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def fetch_intent
    @intent = @assistant.intents.find(params[:id])
  end

  def permitted_params
    params.require(:ai_intent).permit(:name, :triggers, :action, :active, :position, action_payload: {})
  end
end
