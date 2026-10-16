class Api::V1::Accounts::InboxGroupsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox_group, only: [:update, :destroy]
  before_action :check_authorization

  def index
    @inbox_groups = Current.account.inbox_groups.order(:position, :name)
  end

  def create
    @inbox_group = Current.account.inbox_groups.create!(permitted_params)
  end

  def update
    @inbox_group.update!(permitted_params.except(:kind))
  end

  def destroy
    @inbox_group.destroy!
    head :ok
  end

  private

  def fetch_inbox_group
    @inbox_group = Current.account.inbox_groups.find(params[:id])
  end

  def permitted_params
    params.require(:inbox_group).permit(:name, :kind, :position)
  end
end
