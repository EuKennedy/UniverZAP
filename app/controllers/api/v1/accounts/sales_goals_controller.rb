class Api::V1::Accounts::SalesGoalsController < Api::V1::Accounts::BaseController
  before_action :fetch_sales_goal, except: [:index, :create]
  before_action :authorize_action

  def index
    @sales_goals = policy_scope(Current.account.sales_goals.where(active: true)).includes(:user)
  end

  def create
    @sales_goal = Current.account.sales_goals.create!(permitted_params)
    render partial: 'sales_goal', locals: { sales_goal: @sales_goal }
  end

  def update
    @sales_goal.update!(permitted_params)
    render partial: 'sales_goal', locals: { sales_goal: @sales_goal }
  end

  def destroy
    @sales_goal.destroy!
    head :ok
  end

  private

  def fetch_sales_goal
    @sales_goal = Current.account.sales_goals.find(params[:id])
  end

  def authorize_action
    case action_name
    when 'index', 'create'
      authorize(SalesGoal)
    else
      authorize(@sales_goal)
    end
  end

  def permitted_params
    params.require(:sales_goal).permit(:user_id, :period, :target_amount, :active, :name, :unit)
  end
end
