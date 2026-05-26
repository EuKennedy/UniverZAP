class Lgpd::DeletionMailer < ApplicationMailer
  def scheduled(user)
    @user = user
    @scheduled_at = user.scheduled_for_deletion_at
    mail(to: user.email, subject: I18n.t('lgpd.deletion_mailer.scheduled.subject'))
  end

  def cancelled(user)
    @user = user
    mail(to: user.email, subject: I18n.t('lgpd.deletion_mailer.cancelled.subject'))
  end

  def purged(email)
    @email = email
    mail(to: email, subject: I18n.t('lgpd.deletion_mailer.purged.subject'))
  end
end
