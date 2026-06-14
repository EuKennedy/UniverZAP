class BroadcastPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def show?
    @account_user.present?
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

  def launch?
    @account_user.administrator?
  end

  def pause?
    @account_user.administrator?
  end

  def audience_preview?
    @account_user.present?
  end

  def templates?
    @account_user.present?
  end

  def recipients?
    @account_user.present?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account&.id)
    end
  end
end
