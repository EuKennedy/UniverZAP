class Lgpd::ScheduleDeletionService
  RETENTION_WINDOW = 30.days

  class InvalidPassword < StandardError; end

  def initialize(user, current_password:)
    @user = user
    @current_password = current_password
  end

  # LGPD Art. 18 VI — solicita eliminação. Marca o usuário com uma janela
  # de 30 dias antes do purge final. Durante esse período o usuário pode
  # cancelar via dashboard, mas qualquer login mostra o banner regressivo.
  def call
    raise InvalidPassword unless @user.valid_password?(@current_password.to_s)

    @user.update!(scheduled_for_deletion_at: RETENTION_WINDOW.from_now)
    Lgpd::DeletionMailer.scheduled(@user).deliver_later
    @user
  end
end
