# Uma mensagem para UMA conversa que sai numa hora marcada: agendada à mão
# pelo atendente (composer ou ficha da cliente) ou gerada por uma sequência
# (lembrete antes do horário, pós-atendimento depois).
#
# O texto guardado é o modelo (com {primeiro_nome}, spintax…); a versão final
# é montada na hora do envio, para refletir o nome e o serviço daquele momento.
# Quem solta o envio é o ScheduledMessages::DueScannerJob, minuto a minuto:
# editar ou cancelar é só um update na linha, sem job antigo no Redis.
# == Schema Information
#
# Table name: scheduled_messages
#
#  id                  :bigint           not null, primary key
#  cancel_if_reply     :boolean          default(TRUE), not null
#  cancel_reason       :string
#  content             :text             not null
#  error               :string
#  respect_window      :boolean          default(FALSE), not null
#  send_at             :datetime         not null
#  sent_at             :datetime
#  sequence_step       :integer
#  status              :integer          default("scheduled"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  contact_id          :bigint           not null
#  conversation_id     :bigint           not null
#  created_by_id       :bigint
#  inbox_id            :bigint           not null
#  message_id          :bigint
#  message_sequence_id :bigint
#
# Indexes
#
#  index_scheduled_messages_on_account_id           (account_id)
#  index_scheduled_messages_on_contact_id           (contact_id)
#  index_scheduled_messages_on_conversation_id      (conversation_id)
#  index_scheduled_messages_on_created_by_id        (created_by_id)
#  index_scheduled_messages_on_inbox_id             (inbox_id)
#  index_scheduled_messages_on_message_sequence_id  (message_sequence_id)
#  index_scheduled_messages_on_status_and_send_at   (status,send_at)
#
class ScheduledMessage < ApplicationRecord
  CONTENT_LIMIT = 4096

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :contact
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :message_sequence, optional: true

  # scheduled — espera send_at.
  # sending   — reservada pelo scanner, envio em andamento.
  # sent      — virou mensagem na conversa (message_id).
  # cancelled — cancelada (cancel_reason: manual, customer_replied, opted_out, rescheduled).
  # failed    — o envio levantou erro; ver `error`.
  enum status: { scheduled: 0, sending: 1, sent: 2, cancelled: 3, failed: 4 }, _prefix: :status

  validates :content, presence: true, length: { maximum: CONTENT_LIMIT }
  validates :send_at, presence: true
  validate :send_at_in_future, if: -> { status_scheduled? && will_save_change_to_send_at? && created_by_id.present? }

  before_validation :copy_conversation_refs, on: :create

  scope :pending, -> { status_scheduled }
  scope :due, -> { status_scheduled.where(send_at: ..Time.current) }

  def cancel!(reason)
    update!(status: :cancelled, cancel_reason: reason)
  end

  private

  def copy_conversation_refs
    return if conversation.blank?

    self.account_id ||= conversation.account_id
    self.inbox_id ||= conversation.inbox_id
    self.contact_id ||= conversation.contact_id
  end

  # Uma folga de um minuto: quem escolhe "agora + 1 min" não pode tomar erro
  # porque o request demorou.
  def send_at_in_future
    return if send_at.blank? || send_at > 1.minute.ago

    errors.add(:send_at, I18n.t('scheduled_messages.errors.in_past'))
  end
end
