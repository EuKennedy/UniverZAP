# Mensagens automáticas presas ao horário agendado da cliente
# (`data_agendamento` da conversa, gravado pelo "Agendar" da ficha):
# ex.: lembrete 1 dia antes e pós-atendimento 2 dias depois.
#
# Nasce DESLIGADA. Número não oficial: nada sai sozinho até o dono ler os
# textos e ligar a sequência. Cada passo vira uma ScheduledMessage com
# `respect_window`, então nunca sai fora do horário comercial do salão.
#
# steps: [{ "offset_minutes": -1440, "text": "Oi {primeiro_nome}…" }]
#   offset negativo = antes do horário; positivo = depois.
# == Schema Information
#
# Table name: message_sequences
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(FALSE), not null
#  name       :string           not null
#  steps      :jsonb            not null
#  trigger    :string           default("appointment"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  inbox_id   :bigint
#
# Indexes
#
#  index_message_sequences_on_account_id  (account_id)
#  index_message_sequences_on_inbox_id    (inbox_id)
#
class MessageSequence < ApplicationRecord
  TRIGGERS = %w[appointment].freeze
  MAX_STEPS = 5
  # Um lembrete a mais de 30 dias do horário não é lembrete.
  MAX_OFFSET_MINUTES = 30 * 24 * 60

  belongs_to :account
  belongs_to :inbox, optional: true
  has_many :scheduled_messages, dependent: :nullify

  validates :name, presence: true
  validates :trigger, inclusion: { in: TRIGGERS }
  validate :steps_shape

  scope :enabled, -> { where(enabled: true) }

  def normalized_steps
    Array(steps).map do |step|
      { 'offset_minutes' => step['offset_minutes'].to_i, 'text' => step['text'].to_s.strip,
        'cancel_if_reply' => ActiveModel::Type::Boolean.new.cast(step.fetch('cancel_if_reply', true)) != false }
    end
  end

  private

  def steps_shape
    list = normalized_steps
    return errors.add(:steps, I18n.t('scheduled_messages.errors.sequence_steps_required')) if list.empty?
    return errors.add(:steps, I18n.t('scheduled_messages.errors.sequence_too_many_steps', count: MAX_STEPS)) if list.size > MAX_STEPS

    invalid = list.any? { |step| step['text'].blank? || step['offset_minutes'].abs > MAX_OFFSET_MINUTES || step['offset_minutes'].zero? }
    errors.add(:steps, I18n.t('scheduled_messages.errors.sequence_step_invalid')) if invalid
  end
end
