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

  def move?
    update?
  end

  def attach_conversation?
    update?
  end

  def detach_conversation?
    update?
  end

  def destroy?
    @account_user.administrator? || assignee?
  end

  private

  def funnel_visible?
    # Member actions pass a KanbanTask instance, so we can check the parent
    # funnel directly. List/create actions hit `authorize(@funnel, ...)` in
    # the controller — they never reach this branch. Bail out safely if the
    # record is a class (older callers) so we don't 500 on `Class#funnel`.
    return false unless record.is_a?(KanbanTask)
    return false if record.funnel.blank?

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
