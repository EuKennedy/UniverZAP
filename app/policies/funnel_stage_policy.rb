class FunnelStagePolicy < ApplicationPolicy
  def index?
    funnel_visible?
  end

  def show?
    funnel_visible?
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

  def funnel_visible?
    return false if record&.funnel.blank?

    FunnelPolicy.new(@user_context, record.funnel).show?
  end
end
