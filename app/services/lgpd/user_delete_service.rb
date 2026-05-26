class Lgpd::UserDeleteService
  def initialize(user)
    @user = user
  end

  # LGPD Art. 18 VI — elimina o titular e seus vínculos diretos. Devise
  # confirma o destroy; cascades em FKs cuidam de message_threads /
  # notifications / etc. Workspaces órfãos (último admin saindo) ficam
  # intactos: operador faz transferência via super_admin antes.
  def call
    ActiveRecord::Base.transaction do
      anonymize_audits
      @user.account_users.destroy_all
      @user.access_token&.destroy
      @user.destroy!
    end
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
