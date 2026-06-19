class Api::V1::Accounts::ChatflowNodesController < Api::V1::Accounts::BaseController
  before_action :fetch_chatflow
  before_action :fetch_node, only: [:update, :destroy]
  before_action :authorize_action

  def create
    @node = @chatflow.nodes.new(permitted_params.merge(account: Current.account))
    @node.save!
    render :show
  end

  def update
    @node.update!(permitted_params)
    render :show
  end

  def destroy
    @node.destroy!
    head :ok
  end

  private

  def fetch_chatflow
    @chatflow = Current.account.chatflows.find(params[:chatflow_id])
  end

  def fetch_node
    @node = @chatflow.nodes.find(params[:id])
  end

  # Node CRUD is structural authoring — gate it on the parent chatflow so
  # only admins (per ChatflowPolicy) can reshape a flow's graph.
  def authorize_action
    authorize(@chatflow, :update?)
  end

  def permitted_params
    permitted = params.require(:chatflow_node).permit(:kind, :name, :position_x, :position_y)
    # Only touch `config` when the request actually carries it. A drag/position
    # update sends just the coordinates — merging config:{} there would wipe the
    # node's text/options/labels. Persist config solely on real config edits.
    permitted[:config] = node_config if params.require(:chatflow_node).key?(:config)
    permitted
  end

  # `config` is a freeform jsonb payload whose shape depends on the node
  # kind (text + media for messages, options[] for menus, label_ids for
  # categorization). Admin-only endpoint + model-level normalization make
  # the raw passthrough safe; we coerce to a plain hash so strong-params
  # can't choke on the mixed nested shape.
  def node_config
    raw = params.require(:chatflow_node)[:config]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end
end
