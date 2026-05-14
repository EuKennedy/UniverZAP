class KanbanTaskPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def show?
    funnel_visible?
  end

  def create?
    funnel_visible?
  end

  def update?
    funnel_visible?
  end

  def destroy?
    @account_user.administrator? || assignee?
  end

  private

  def funnel_visible?
    return false if record&.funnel.blank?

    FunnelPolicy.new(@user_context, record.funnel).show?
  end

  def assignee?
    record.kanban_task_assignees.exists?(user_id: @user.id)
  end

  class Scope < Scope
    def resolve
      visible_funnel_ids = FunnelPolicy::Scope.new(user_context, Funnel).resolve.pluck(:id)
      scope.where(account_id: account&.id, funnel_id: visible_funnel_ids)
    end
  end
end
