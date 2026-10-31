# Rollout das mudanças de WAHA nas sessões e apps que já existem
# (Whatsapp::WahaRollout). As duas tarefas podem rodar mais de uma vez.
namespace :waha do
  # Ordem do HMAC: definir WAHA_WEBHOOK_HMAC_KEY -> rodar esta tarefa -> ligar
  # WAHA_WEBHOOK_HMAC_REQUIRED.
  #
  #   bundle exec rake waha:sync_webhooks
  desc 'Reapply the UniverZAP webhook (retries + HMAC) on every WAHA session that already uses it'
  task sync_webhooks: :environment do
    Whatsapp::WahaRollout.new.sync_webhooks!
  end

  #   bundle exec rake waha:rebrand
  #   APAGAR_DOACOES=1 bundle exec rake waha:rebrand
  desc 'Rebrand the WAHA Chatwoot app notifications contact as UniverZAP'
  task rebrand: :environment do
    Whatsapp::WahaRollout.new.rebrand!(delete_donations: ENV['APAGAR_DOACOES'] == '1')
  end
end
