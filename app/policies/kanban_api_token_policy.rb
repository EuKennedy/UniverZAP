class KanbanApiTokenPolicy < ApplicationPolicy
  # Tokens are powerful — only admins manage them.
  def index?
    @account_user.administrator?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def destroy?
    index?
  end

  def revoke?
    index?
  end
end
