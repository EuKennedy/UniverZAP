class FunnelCustomFieldPolicy < ApplicationPolicy
  # Missing policy was the silent 500 cause when admins opened the kanban
  # funnel "Settings" tab and the page fired GET
  # /api/v1/accounts/:id/funnels/:funnel_id/funnel_custom_fields. The base
  # controller's `check_authorization` resolved the class from the
  # controller name and Pundit raised `NotDefinedError` because no
  # corresponding policy was on disk — which surfaced to the operator as
  # an opaque server error and blocked every settings entry point.

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

  def reorder?
    @account_user.administrator?
  end

  private

  # The `check_authorization` callback in `Api::BaseController` hands
  # Pundit the class itself for `:index`/`:create` actions — at that point
  # `record` is `FunnelCustomField` (the class), not an instance, and we
  # can't reach `record.funnel`. Fall back to the account-membership gate.
  # For member actions Pundit gets the instance and we defer to
  # `FunnelPolicy#show?` so visibility stays in lockstep with the parent
  # funnel.
  def funnel_visible?
    return @account_user.present? if record.is_a?(Class)
    return false if record.funnel.blank?

    FunnelPolicy.new(@user_context, record.funnel).show?
  end
end
