class TaskViewPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    return false unless index?
    return true  if record.is_a?(Class)

    record.user_id.nil? || record.user_id == @user.id || @account_user.administrator?
  end

  def create?
    index?
  end

  def update?
    can_mutate?
  end

  def destroy?
    can_mutate?
  end

  def set_default?
    show?
  end

  private

  def can_mutate?
    return false unless index?
    return true if @account_user.administrator?

    record.is_a?(TaskView) && record.user_id == @user.id
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account&.id)
    end
  end
end
