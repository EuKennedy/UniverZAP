# O WhatsApp do cliente que vai para a agenda do salão.
#
# ## Por que isto existe como classe
#
# Existia como uma linha só, dentro de SchedulingTools:
#
#     @contact[:phone].presence || input['client_phone']
#
# Aquele `||` custou caro e está documentado por dados, não por suposição. Numa
# conversa de teste em que o contato não tinha telefone, o modelo preencheu o
# campo três vezes, com três números diferentes e inventados, na mesma conversa:
# +5500000000000, +5511999999999 e +5531999999999. As consequências saíram todas
# de uma vez:
#
#   * a chave de idempotência inclui o telefone, então cada número inventado
#     virou uma chave diferente, e o agente AGENDOU DUAS VEZES o mesmo horário,
#     bateu no próprio agendamento e disse ao cliente que a vaga tinha acabado
#     de ser preenchida;
#   * `meus_agendamentos` é escopado por telefone no salão, então o cliente
#     nunca mais encontraria o próprio horário;
#   * e a confirmação automática do belezaki (fireBookingEffects) tenta resolver
#     o número no WhatsApp antes de enviar. Número inventado não resolve, e o
#     disparo morre em silêncio, que foi exatamente o sintoma relatado.
#
# ## A regra
#
# O registro de contato é a ÚNICA fonte para escrever na agenda. Um número que o
# modelo digitou é um número que o modelo pode ter inventado. Quando o contato
# não tem telefone, a ferramenta recusa e manda perguntar, e o número que o
# cliente responder passa por `register`, que só aceita se ele tiver mesmo
# aparecido numa mensagem RECEBIDA. Isso fecha a porta da invenção sem fechar a
# porta do atendimento.
class Ai::Belezaki::CustomerPhone
  # Quantas mensagens do cliente olhar para trás procurando o número. Passa de
  # uma conversa inteira de agendamento e ainda assim não é a conversa toda: um
  # número dito há trinta mensagens provavelmente era de outra pessoa.
  LOOKBACK = 12

  # Os últimos dígitos que precisam bater. Dez cobre DDD mais o miolo do número
  # e sobrevive ao cliente escrever "(31) 98495-6383", "31984956383" ou
  # "+55 31 98495 6383", que geram o mesmo rastro depois de tirar a pontuação.
  MATCH_DIGITS = 10

  def initialize(conversation:, fallback: nil)
    @conversation = conversation
    @fallback = fallback
  end

  # O número sob o qual agendar, ou nil. Lê o registro VIVO do contato e não uma
  # cópia feita no começo do turno, porque `register` pode ter gravado o número
  # há três linhas, no mesmo turno.
  def value
    contact&.phone_number.presence || @fallback.presence
  end

  def present?
    value.present?
  end

  # [:ok, telefone] quando grava, [:recusado, motivo] quando não.
  #
  # Nunca levanta: uma falha ao gravar o contato não pode custar a resposta que
  # o cliente está esperando.
  def register(raw)
    digits = normalise(raw)
    return [:recusado, 'Número inválido. Peça o WhatsApp com DDD, por exemplo 31 98765-4321.'] if digits.nil?
    return [:recusado, 'Não vi esse número na conversa. Peça para o cliente digitar o WhatsApp dele.'] unless said_by_customer?(digits)
    return [:recusado, 'Não consigo registrar o número desta conversa.'] if contact.nil?

    contact.update!(phone_number: "+#{digits}")
    [:ok, "+#{digits}"]
  rescue StandardError => e
    Rails.logger.warn("[Belezaki] could not store customer phone: #{e.message}")
    [:recusado, 'Não consegui registrar o número agora.']
  end

  private

  def contact
    @conversation&.contact
  end

  # Devolve os 13 dígitos de um celular brasileiro (55 + DDD + 9 dígitos), ou
  # nil. O nono dígito é exigido porque o destino é o WhatsApp: um fixo aceita a
  # reserva e nunca recebe a confirmação, que é a pior combinação possível.
  #
  # Nenhum DDD brasileiro tem zero em qualquer das duas posições, e é essa regra
  # que reprova o `+5500000000000` que o modelo inventou.
  def normalise(raw)
    digits = raw.to_s.gsub(/\D/, '')
    digits = digits.delete_prefix('55') if digits.length > 11
    return nil unless digits.length == 11

    ddd = digits[0, 2]
    return nil if ddd.include?('0')
    return nil unless digits[2] == '9'

    "55#{digits}"
  end

  # A trava contra invenção: o número tem que ter saído da boca do cliente. O
  # modelo pode repetir o que leu, nunca criar o que não existe.
  def said_by_customer?(digits)
    heard.include?(digits.last(MATCH_DIGITS))
  end

  def heard
    @heard ||= incoming_contents.join(' ').gsub(/\D/, '')
  end

  def incoming_contents
    return [] if @conversation.blank?

    @conversation.messages.where(message_type: :incoming)
                 .reorder(created_at: :desc).limit(LOOKBACK).pluck(:content).compact
  rescue StandardError
    []
  end
end
