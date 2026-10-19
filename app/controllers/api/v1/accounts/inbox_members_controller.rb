class Api::V1::Accounts::InboxMembersController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :current_agents_ids, only: [:create, :update]

  def show
    authorize @inbox, :show?
    fetch_updated_agents
  end

  def create
    authorize @inbox, :create?
    ActiveRecord::Base.transaction do
      @inbox.add_members(agents_to_be_added_ids)
      apply_capacities
    end
    fetch_updated_agents
  end

  def update
    authorize @inbox, :update?
    update_agents_list
    fetch_updated_agents
  end

  def destroy
    authorize @inbox, :destroy?
    ActiveRecord::Base.transaction do
      @inbox.remove_members(params[:user_ids])
    end
    head :ok
  end

  private

  def fetch_updated_agents
    @agents = Current.account.users.where(id: @inbox.members.select(:user_id))
    @capacities = @inbox.inbox_members.pluck(:user_id, :assignment_capacity).to_h
  end

  def update_agents_list
    # get all the user_ids which the inbox currently has as members.
    # get the list of  user_ids from params
    # the missing ones are the agents which are to be deleted from the inbox
    # the new ones are the agents which are to be added to the inbox
    ActiveRecord::Base.transaction do
      @inbox.add_members(agents_to_be_added_ids)
      @inbox.remove_members(agents_to_be_removed_ids)
      apply_capacities
    end
  end

  # capacities: [{ user_id:, assignment_capacity: }] — blank clears the limit.
  def apply_capacities
    Array(params[:capacities]).each do |entry|
      member = @inbox.inbox_members.find_by(user_id: entry[:user_id])
      member&.update!(assignment_capacity: entry[:assignment_capacity].presence)
    end
  end

  def agents_to_be_added_ids
    params[:user_ids] - @current_agents_ids
  end

  def agents_to_be_removed_ids
    @current_agents_ids - params[:user_ids]
  end

  def current_agents_ids
    @current_agents_ids = @inbox.members.pluck(:id)
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end
end
