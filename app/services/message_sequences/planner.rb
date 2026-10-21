# Transforma o horário agendado da conversa (`data_agendamento`, do "Agendar"
# da ficha) nas mensagens das sequências LIGADAS da conta: cada passo vira uma
# ScheduledMessage em `horário + offset`.
#
# Roda de novo sempre que o horário muda: o que estava pendente da sequência
# é cancelado (`rescheduled`) e refeito. Horário apagado = tudo cancelado.
# Um passo que já passou não é criado — remarcar para amanhã não manda o
# lembrete "1 dia antes" agora.
class MessageSequences::Planner
  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
  end

  def perform
    appointment = appointment_time
    pending.find_each { |scheduled| scheduled.cancel!('rescheduled') }
    return [] if appointment.nil?

    sequences.flat_map { |sequence| plan(sequence, appointment) }
  end

  private

  def plan(sequence, appointment)
    sequence.normalized_steps.each_with_index.filter_map do |step, index|
      send_at = fit_in_window(appointment + step['offset_minutes'].minutes, before: step['offset_minutes'].negative?, limit: appointment)
      next if send_at.nil? || send_at <= Time.current

      @conversation.scheduled_messages.create!(
        message_sequence: sequence, sequence_step: index, content: step['text'], send_at: send_at,
        respect_window: true, cancel_if_reply: step['cancel_if_reply']
      )
    end
  end

  # Lembrete "antes" que cai fora do horário comercial volta para a última hora
  # aberta antes dele (nunca depois do próprio horário marcado); "depois" anda
  # para a próxima abertura.
  def fit_in_window(time, before:, limit:)
    return time if window.open?(time)
    return window.next_open(time) unless before

    candidate = time
    168.times do
      candidate -= 1.hour
      return candidate.change(min: 0) + 30.minutes if window.open?(candidate) && candidate < limit
    end
    nil
  end

  def pending
    ScheduledMessage.pending.where(conversation_id: @conversation.id).where.not(message_sequence_id: nil)
  end

  def sequences
    @account.message_sequences.enabled.where(trigger: 'appointment').where(inbox_id: [nil, @conversation.inbox_id])
  end

  def appointment_time
    raw = (@conversation.custom_attributes || {})['data_agendamento']
    raw.present? ? Time.zone.parse(raw.to_s) : nil
  rescue ArgumentError
    nil
  end

  def window
    @window ||= Broadcasts::SendWindow.default_for(@account)
  end
end
