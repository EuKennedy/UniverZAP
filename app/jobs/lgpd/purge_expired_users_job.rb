class Lgpd::PurgeExpiredUsersJob < ApplicationJob
  queue_as :scheduled_jobs

  # Cron diário: purga definitivamente usuários cuja janela de retenção
  # já expirou. Cada purge é isolado em transação dentro de
  # Lgpd::UserDeleteService.
  def perform
    User.where('scheduled_for_deletion_at <= ?', Time.current).find_each do |user|
      Lgpd::UserDeleteService.new(user).call
    rescue StandardError => e
      Rails.logger.error("[lgpd.purge] user=#{user.id} failed: #{e.class} #{e.message}")
    end
  end
end
