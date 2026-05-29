class TeamChatChannelPolicy < ApplicationPolicy
  # Read + participate: any member of the account (admin or agent).
  def index?
    member?
  end

  def show?
    member?
  end

  # Reading / posting messages flows through the channel policy so the
  # messages controller has a single membership gate to authorize against.
  def messages?
    member?
  end

  def post_message?
    member?
  end

  # Channel lifecycle (create / rename / archive) is admin-only — keeps the
  # workspace structure from sprawling. The "+" button is hidden for agents
  # in the UI, this is the server-side enforcement.
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

  def member?
    @account_user.administrator? || @account_user.agent?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account&.id)
    end
  end
end
