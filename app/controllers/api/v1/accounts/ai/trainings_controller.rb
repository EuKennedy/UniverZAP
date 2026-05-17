class Api::V1::Accounts::Ai::TrainingsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_training, only: [:update, :destroy]

  def index
    @trainings = @assistant.trainings.order(created_at: :desc)
  end

  def create
    @training = @assistant.trainings.create!(permitted_params.merge(account: Current.account, status: 'ready'))
    render :show
  end

  def update
    @training.update!(permitted_params)
    render :show
  end

  def destroy
    @training.destroy!
    head :ok
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def fetch_training
    @training = @assistant.trainings.find(params[:id])
  end

  def permitted_params
    params.require(:ai_training).permit(:title, :source_type, :category, :content)
  end
end
