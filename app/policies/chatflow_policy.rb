class ChatflowPolicy < ApplicationPolicy
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

  # Member actions (activate/archive/test/stop_test/run) authorize against the
  # chatflow instance, so Pundit looks up these predicates by action name.
  # Without them Pundit raises NotDefinedError → HTTP 500 on the builder.
  def activate?
    @account_user.administrator?
  end

  def archive?
    @account_user.administrator?
  end

  def test?
    @account_user.administrator?
  end

  def stop_test?
    @account_user.administrator?
  end

  def run?
    @account_user.administrator?
  end

  # Modelos prontos e opções do editor (listas, outros fluxos, disparos).
  def templates?
    @account_user.present?
  end

  def from_template?
    @account_user.administrator?
  end

  def options?
    @account_user.present?
  end

  def funnel?
    @account_user.present?
  end

  # Simular não envia nada (transação desfeita), mas é ferramenta de quem edita.
  def simulate?
    @account_user.administrator?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account&.id)
    end
  end
end
