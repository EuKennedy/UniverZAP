class Lgpd::DeletionMailer < ApplicationMailer
  def scheduled(user)
    @user = user
    @scheduled_at = user.scheduled_for_deletion_at
    mail(
      to: user.email,
      subject: '[UniverZAP] Sua exclusão de conta foi agendada'
    )
  end

  def cancelled(user)
    @user = user
    mail(
      to: user.email,
      subject: '[UniverZAP] Exclusão de conta cancelada'
    )
  end

  def purged(email)
    @email = email
    mail(
      to: email,
      subject: '[UniverZAP] Sua conta foi excluída permanentemente'
    )
  end
end
