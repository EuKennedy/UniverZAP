# Decide, na hora do envio, se uma mensagem automática NÃO deve sair para o
# contato. Vale para disparo em massa e para sequências; a mensagem agendada à
# mão só olha o opt-out (quem agendou já conhecia a conversa).
#
# Motivos (gravados em `skip_reason`):
#   opted_out        — a cliente pediu para não receber (Broadcasts::OptOutService).
#   no_phone         — sem número (ex.: contato @lid).
#   recent_activity  — a cliente escreveu, ou um atendente respondeu, nas
#                      últimas `quiet_hours`: ela está em atendimento e uma
#                      mensagem de campanha no meio da conversa soa robô.
class Broadcasts::RecipientGuard
  OPT_OUT_ATTRIBUTE = 'opt_out_disparos'.freeze
  # Mesmo texto de Message::PHONE_REPLY_NOTE_PATTERN, em forma de LIKE.
  PHONE_REPLY_LIKE = ['%📱 Enviado do WhatsApp%', '%📱 Sent from WhatsApp%'].freeze

  def self.opted_out?(contact)
    ActiveModel::Type::Boolean.new.cast((contact.custom_attributes || {})[OPT_OUT_ATTRIBUTE]) || false
  end

  # Versão em lote para a pré-visualização: { opted_out: [ids], recent_activity: [ids] }.
  def self.blocked_ids(account, ids, quiet_hours:)
    opted = account.contacts.where(id: ids).where("contacts.custom_attributes->>'#{OPT_OUT_ATTRIBUTE}' = 'true'").pluck(:id)
    recent = quiet_hours.to_i.positive? ? recent_contact_ids(account, ids - opted, quiet_hours.to_i) : []
    { opted_out: opted, recent_activity: recent }
  end

  def self.recent_contact_ids(account, ids, quiet_hours)
    return [] if ids.empty?

    activity_scope(Message.unscope(:order).where(account_id: account.id).joins(:conversation).where(conversations: { contact_id: ids }), quiet_hours)
      .distinct.pluck('conversations.contact_id')
  end

  # Mensagem da cliente, resposta de um atendente (sender User) ou resposta
  # pelo celular (a nota "📱 Enviado do WhatsApp" que o app da WAHA grava).
  # Disparo e bot saem sem sender User e não contam como "em atendimento".
  def self.activity_scope(scope, quiet_hours)
    scope.where(created_at: quiet_hours.hours.ago..)
         .where('(messages.private = FALSE AND (messages.message_type = ? OR (messages.message_type = ? AND messages.sender_type = ?))) ' \
                'OR (messages.private = TRUE AND (messages.content LIKE ? OR messages.content LIKE ?))',
                Message.message_types[:incoming], Message.message_types[:outgoing], 'User', *PHONE_REPLY_LIKE)
  end

  def initialize(contact:, quiet_hours:)
    @contact = contact
    @quiet_hours = quiet_hours.to_i
  end

  def skip_reason
    return 'opted_out' if self.class.opted_out?(@contact)
    return 'no_phone' if @contact.phone_number.blank?
    return 'recent_activity' if recent_activity?

    nil
  end

  private

  def recent_activity?
    return false if @quiet_hours <= 0

    scope = Message.where(account_id: @contact.account_id, conversation_id: @contact.conversations.select(:id))
    self.class.activity_scope(scope, @quiet_hours).exists?
  end
end
