# Quando o WhatsApp trava o número para contatos novos (463 Reachout Timelock,
# 475 Message Capping), um disparo que segue mandando só queima o lote: cada
# envio é recusado, o número fica pior visto e a fila do Sidekiq gira em falso.
# Esta classe guarda, por inbox, até quando o WhatsApp disse que a trava vale,
# e Broadcasts::DispatchJob espera esse horário em vez de mandar.
#
# Só a prospecção espera. Resposta em conversa que já existe continua saindo:
# o WhatsApp bloqueia só o 1:1 com quem ainda não tem conversa.
class Whatsapp::WahaOutreachGuard
  TIMELOCK = 463
  CAPPING = 475
  KEY = 'waha:outreach_block:%<inbox_id>s:%<code>s'.freeze
  # Quando a WAHA não informa o fim (ou não responde), uma espera curta e o
  # próximo erro arma de novo. O ciclo do capping pode durar semanas.
  FALLBACK = { TIMELOCK => 6.hours, CAPPING => 24.hours }.freeze
  MAX_BLOCK = 35.days

  # "server returned error 463" vem no corpo da resposta da WAHA.
  def self.code_in(text)
    text.to_s[/error (#{TIMELOCK}|#{CAPPING})\b/, 1]&.to_i
  end

  def initialize(inbox)
    @inbox = inbox
  end

  # O fim da trava mais longa que estiver valendo, ou nil.
  def blocked_until
    ends = [TIMELOCK, CAPPING].filter_map { |code| ::Redis::Alfred.get(key(code)) }
    ends.map { |ts| Time.zone.at(ts.to_i) }.select(&:future?).max
  end

  # Um envio acabou de falhar com 463/475: pergunta à WAHA quando acaba.
  def trip!(code)
    block!(code, restriction_end(code) || FALLBACK.fetch(code).from_now)
  end

  # A WAHA reemite session.status WORKING com o estado das travas sempre que o
  # WhatsApp muda alguma: liga, atualiza ou desliga cada uma.
  def sync!(data)
    data = data.to_h.with_indifferent_access
    sync_timelock(data[:reachoutTimelock]) if data.key?(:reachoutTimelock)
    sync_capping(data[:messageCapping]) if data.key?(:messageCapping)
  end

  private

  def sync_timelock(lock)
    return clear!(TIMELOCK) unless lock.is_a?(Hash) && lock[:isActive]

    block!(TIMELOCK, lock[:timeEnforcementEnds].present? ? Time.zone.at(lock[:timeEnforcementEnds].to_i) : FALLBACK[TIMELOCK].from_now)
  end

  def sync_capping(cap)
    return clear!(CAPPING) unless cap.is_a?(Hash) && cap[:cappingStatus] == 'CAPPED'

    block!(CAPPING, cap[:cycleEnd].present? ? Time.zone.at(cap[:cycleEnd].to_i) : FALLBACK[CAPPING].from_now)
  end

  def block!(code, until_time)
    ttl = [(until_time - Time.current).ceil, MAX_BLOCK.to_i].min
    return clear!(code) unless ttl.positive?

    Rails.logger.warn("[WAHA outreach] inbox=#{@inbox.id} code=#{code} blocked until #{until_time.iso8601}")
    ::Redis::Alfred.set(key(code), until_time.to_i, ex: ttl)
  end

  def clear!(code)
    ::Redis::Alfred.delete(key(code))
  end

  def restriction_end(code)
    service = @inbox.channel.provider_service.session_service
    ts = code == TIMELOCK ? service.timelock&.dig('timeEnforcementEnds') : service.capping&.dig('cycleEnd')
    ts.present? ? Time.zone.at(ts.to_i) : nil
  rescue StandardError => e
    Rails.logger.warn("[WAHA outreach] inbox=#{@inbox.id} could not read code=#{code} state: #{e.message}")
    nil
  end

  def key(code)
    format(KEY, inbox_id: @inbox.id, code: code)
  end
end
