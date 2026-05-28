class KanbanWebhookSubscriptionPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def update?
    index?
  end

  def destroy?
    index?
  end

  def test?
    index?
  end
end
