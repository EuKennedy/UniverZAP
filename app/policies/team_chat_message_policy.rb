class TeamChatMessagePolicy < ApplicationPolicy
  # Only the author can edit their own message. Admins cannot rewrite
  # someone else's words — that's a trust line we don't cross.
  def update?
    author?
  end

  # Authors delete their own; admins can remove anyone's (moderation).
  def destroy?
    author? || @account_user.administrator?
  end

  private

  def author?
    record.is_a?(TeamChatMessage) && record.user_id == @user.id
  end
end
