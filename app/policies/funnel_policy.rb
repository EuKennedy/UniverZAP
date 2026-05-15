class FunnelPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def show?
    member_access?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  private

  def member_access?
    return true if @account_user.administrator?
    return true if record.funnel_agents.empty?

    record.funnel_agents.exists?(user_id: @user.id)
  end

  class Scope < Scope
    def resolve
      return scope.where(account_id: account&.id) if account_user&.administrator?

      scope.where(account_id: account&.id).left_joins(:funnel_agents)
           .where('funnel_agents.user_id IS NULL OR funnel_agents.user_id = ?', user.id)
           .distinct
    end
  end
end
