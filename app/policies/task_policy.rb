class TaskPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    # Any agent in the account can create tasks (assign to self or
    # others). Stricter gating lives on assign?/complete? for the
    # actions that change ownership.
    index?
  end

  def update?
    can_mutate?
  end

  def destroy?
    can_mutate?
  end

  def assign?
    @account_user.administrator? || creator?
  end

  def unassign?
    assign?
  end

  def complete?
    assign?
  end

  def comment?
    show?
  end

  def activities?
    show?
  end

  def add_comment?
    comment?
  end

  def bulk?
    index?
  end

  def team_workload?
    @account_user.administrator?
  end

  def reports?
    @account_user.administrator?
  end

  def convert_to_kanban_card?
    can_mutate?
  end

  private

  def can_mutate?
    @account_user.administrator? || creator? || assignee?
  end

  def creator?
    record.is_a?(Task) && record.created_by_user_id == @user.id
  end

  def assignee?
    return false unless record.is_a?(Task)

    record.task_assignees.exists?(user_id: @user.id)
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account&.id)
    end
  end
end
