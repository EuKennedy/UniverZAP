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

  # Saved edits mark the document ready, the same way creating one does.
  # `status` defaults to `pending` at the column level and the retrieval only
  # reads `ready`, so a document that ever landed pending was invisible to the
  # agent forever — the operator wrote rules, saw them listed, and the agent
  # never received a word of them. There is no async ingestion to wait for
  # (grounding chunks at query time), so a document with content IS ready, and
  # re-saving it is the way out that did not exist before.
  def update
    @training.update!(permitted_params.merge(status: 'ready'))
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
