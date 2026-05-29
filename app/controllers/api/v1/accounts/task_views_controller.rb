# CRUD for saved task views — the user's filter presets. `set_default`
# is a separate endpoint so the dashboard can toggle which preset
# auto-applies on `/tasks` open without re-PATCHing the whole row.
class Api::V1::Accounts::TaskViewsController < Api::V1::Accounts::BaseController
  before_action :fetch_view, only: [:show, :update, :destroy, :set_default]
  before_action :authorize_action

  def index
    views = Current.account.task_views.visible_to(Current.user.id)
    render json: views.map(&:push_event_data)
  end

  def show
    render json: @view.push_event_data
  end

  def create
    @view = Current.account.task_views.create!(create_params.merge(user_id: owner_user_id))
    render json: @view.push_event_data, status: :created
  end

  def update
    @view.update!(update_params)
    render json: @view.push_event_data
  end

  def destroy
    @view.destroy!
    head :ok
  end

  # Flip this view to the default for the current user. Atomically
  # clears any other default the user might have for the same scope.
  def set_default
    TaskView.transaction do
      Current.account.task_views.where(user_id: @view.user_id, is_default: true).where.not(id: @view.id)
             .update_all(is_default: false) # rubocop:disable Rails/SkipsModelValidations
      @view.update!(is_default: true)
    end
    render json: @view.push_event_data
  end

  private

  def fetch_view
    @view = Current.account.task_views.find(params[:id])
  end

  def authorize_action
    record = %w[index create].include?(action_name) ? TaskView : @view
    authorize(record, "#{action_name}?", policy_class: TaskViewPolicy)
  end

  # Shared views (visible to the whole account) are admin-only and
  # surfaced by passing `shared: true` in the payload. Anyone else
  # gets their own personal view anchored on `Current.user`.
  def owner_user_id
    shared = params.dig(:task_view, :shared).to_s == 'true'
    return nil if shared && Current.account_user.administrator?

    Current.user.id
  end

  def create_params
    params.require(:task_view).permit(:name, :position, :is_default, filters: {})
  end

  def update_params
    params.require(:task_view).permit(:name, :position, :is_default, filters: {})
  end
end
