# Os "reflexos" das mensagens agendadas e dos disparos:
#
# - a cliente escreveu → cancela o que estava agendado para aquela conversa
#   com `cancel_if_reply` (não faz sentido o "oi, sumida!" chegar depois de
#   ela já ter falado) e conta a resposta no relatório do disparo;
# - a cliente pediu para não receber → opt-out (Broadcasts::OptOutService);
# - o horário agendado da conversa mudou → refaz as sequências.
class ScheduledMessageListener < BaseListener
  REPLY_WINDOW = 7.days

  def message_created(event)
    return if sandbox_event?(event)

    message = event.data[:message]
    return if message.blank? || !message.incoming? || message.private?

    cancel_pending(message)
    mark_replied(message)
    Broadcasts::OptOutService.new(message.conversation.contact).perform if Broadcasts::OptOutService.opt_out_text?(message.content)
  end

  def conversation_updated(event)
    return if sandbox_event?(event)

    conversation = event.data[:conversation]
    change = (event.data[:changed_attributes] || {})['custom_attributes']
    return if conversation.blank? || change.blank?

    before, after = change
    return if before.to_h['data_agendamento'] == after.to_h['data_agendamento']

    MessageSequences::Planner.new(conversation).perform
  end

  private

  # Só o que foi agendado ANTES da mensagem dela: com a fila atrasada, uma
  # mensagem antiga processada agora não pode cancelar um agendamento novo.
  def cancel_pending(message)
    ScheduledMessage.pending.where(conversation_id: message.conversation_id, cancel_if_reply: true)
                    .where(created_at: ...message.created_at)
                    .find_each { |scheduled| scheduled.cancel!('customer_replied') }
  end

  def mark_replied(message)
    BroadcastRecipient.where(contact_id: message.conversation.contact_id, status: %i[sent delivered read], replied_at: nil)
                      .where(sent_at: REPLY_WINDOW.ago..message.created_at)
                      .update_all(replied_at: message.created_at, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
