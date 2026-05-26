class Lgpd::UserDeleteService
  def initialize(user)
    @user = user
  end

  # LGPD Art. 18 VI — purga final do titular. Chamado pelo cron
  # Lgpd::PurgeExpiredUsersJob depois da janela de retenção de 30 dias.
  # Anonimiza audits, destrói o User + cascades de FK, e dispara o email
  # de confirmação.
  def call
    final_email = @user.email
    ActiveRecord::Base.transaction do
      anonymize_audits
      @user.account_users.destroy_all
      @user.access_token&.destroy
      @user.destroy!
    end
    Lgpd::DeletionMailer.purged(final_email).deliver_later
  end

  private

  # Deixar audit trail sem PII após exclusão: trocamos o user_id por nil
  # mas mantemos as linhas para preservar histórico operacional. O playbook
  # § 12.1 lista AuditLog como prova de compliance.
  def anonymize_audits
    return unless defined?(Audited::Audit)

    # Audited::Audit rows have no validations to skip — bulk update is
    # appropriate to strip PII without N+1.
    Audited::Audit.where(user: @user).update_all(user_id: nil, user_type: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
