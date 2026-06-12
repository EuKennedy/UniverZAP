class Api::V1::Accounts::ChatflowEdgesController < Api::V1::Accounts::BaseController
  before_action :fetch_chatflow
  before_action :fetch_edge, only: [:destroy]
  before_action :authorize_action

  def create
    @edge = @chatflow.edges.new(permitted_params.merge(account: Current.account))
    @edge.save!
    render :show
  end

  def destroy
    @edge.destroy!
    head :ok
  end

  private

  def fetch_chatflow
    @chatflow = Current.account.chatflows.find(params[:chatflow_id])
  end

  def fetch_edge
    @edge = @chatflow.edges.find(params[:id])
  end

  def authorize_action
    authorize(@chatflow, :update?)
  end

  def permitted_params
    params.require(:chatflow_edge).permit(:source_node_id, :target_node_id, :source_handle)
  end
end
