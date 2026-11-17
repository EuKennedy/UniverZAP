# Rede de segurança contra mensagem perdida: a WAHA desiste depois de três
# tentativas, e uma queda ou erro maior que isso deixava a mensagem fora da caixa
# sem ninguém ver. De hora em hora, cada caixa WAHA pede à própria ponte que traga
# o que faltou das últimas 3 horas. O comando pula o que já entrou e o atraso vira
# a data real em WahaDelayedDelivery.
class Whatsapp::WahaHistoryReconcileJob < ApplicationJob
  queue_as :scheduled_jobs

  COMMAND = 'messages pull 3h -m -g'.freeze
  COMMANDS_CHAT_ID = 'whatsapp.integration'.freeze

  def perform
    Channel::Api.where("additional_attributes->>'source' = ?", 'waha').find_each { |channel| reconcile(channel) }
  end

  private

  def reconcile(channel)
    conversation = commands_conversation(channel.inbox)
    sender = channel.account.administrators.first
    return unless conversation && sender && session_working?(channel)

    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, sender: sender, content: COMMAND
    )
  rescue StandardError => e
    Rails.logger.error("[WAHA] reconciliação da caixa #{channel.inbox&.id} falhou: #{e.message}")
  end

  def commands_conversation(inbox)
    return if inbox.blank?

    inbox.conversations.joins(:contact)
         .where("contacts.custom_attributes->>'waha_whatsapp_chat_id' = ?", COMMANDS_CHAT_ID)
         .reorder(last_activity_at: :desc).first
  end

  def session_working?(channel)
    session_name = channel.additional_attributes['session_name']
    return false if session_name.blank?

    Whatsapp::WahaSessionService.new(session_name: session_name).session.to_h['status'] == 'WORKING'
  end
end
