# Os blocos de automação do Chatflow: pergunta, condição, espera, divisão
# aleatória, ir para outro fluxo, "Digitando…" e lista. Incluído no
# Chatflow::NodeRunnerService (usa @execution, @node, @conversation e
# send_message dele).
module Chatflow::AutomationBlocks
  WAIT_UNITS = { 'minutes' => 1.minute, 'hours' => 1.hour, 'days' => 1.day }.freeze
  MAX_WAIT = 90.days
  MAX_TYPING_SECONDS = 20

  def self.weighted_pick(branches, rng)
    weights = branches.map { |b| b['percent'].to_i.clamp(0, 100) }
    return branches.first unless weights.sum.positive?

    pick = rng.rand(weights.sum)
    branches.zip(weights).find { |_branch, weight| (pick -= weight).negative? }.first
  end

  private

  def question_node
    send_message(content: config_text)
    :wait
  end

  def condition_node
    Chatflow::ConditionEvaluator.new(@conversation, @node.config).handle
  end

  # Programa o relógio e para. Quem solta é o scanner minuto a minuto das
  # mensagens agendadas (ScheduledMessages::DueScannerJob → Chatflow::WaitScanner).
  def wait_node
    @execution.update!(resume_at: wait_until)
    :wait
  end

  def wait_until
    target = if @node.config['mode'] == 'until'
               Time.zone.parse(@node.config['until'].to_s) || Time.current
             else
               Time.current + wait_duration
             end
    target = target.clamp(Time.current, MAX_WAIT.from_now)
    @node.config['respect_window'] ? Broadcasts::SendWindow.default_for(@conversation.account).next_open(target) : target
  end

  def wait_duration
    amount = @node.config['amount'].to_i.clamp(1, 10_000)
    amount * WAIT_UNITS.fetch(@node.config['unit'].to_s, 1.minute)
  end

  # Sorteia uma saída pelos percentuais. Percentual zerado nunca sai; tudo
  # zerado cai na primeira, para o fluxo não parar por configuração pela metade.
  def random_split_node
    branches = Array(@node.config['branches']).map(&:to_h).select { |b| b['value'].present? }
    return :continue if branches.empty?

    Chatflow::AutomationBlocks.weighted_pick(branches, simulation&.rng || Random)['value'].to_s
  end

  def goto_flow_node
    :goto
  end

  # "Digitando…": uma pausa curta antes da próxima mensagem, para o robô não
  # responder em rajada. O WhatsApp via ponte WAHA não recebe o "digitando" de
  # verdade — é só o atraso. Solta pelo Chatflow::ResumeJob (e pelo scanner,
  # se o job se perder).
  def typing_node
    seconds = @node.config['seconds'].to_i.clamp(1, MAX_TYPING_SECONDS)
    @execution.update!(resume_at: seconds.seconds.from_now)
    Chatflow::ResumeJob.set(wait: seconds.seconds).perform_later(@execution.id) unless simulation
    :wait
  end

  def list_action_node
    return :continue unless Chatflow::ListBridge.available?

    Chatflow::ListBridge.apply(@conversation.account, @conversation.contact, @node.config['list_id'], @node.config['action'])
    :continue
  end

  def webhook_node
    url = @node.config['url'].to_s
    return :continue if url.blank?
    return simulated(:skipped_webhook, :continue) if simulation

    method = %w[post get put].include?(@node.config['method']) ? @node.config['method'] : 'post'
    HTTParty.public_send(method, url, body: webhook_payload.to_json,
                                      headers: { 'Content-Type' => 'application/json' }, timeout: 8)
    :continue
  rescue StandardError => e
    Rails.logger.warn("[Chatflow webhook] #{e.message}")
    :continue
  end

  def webhook_payload
    {
      conversation_id: @conversation.display_id,
      inbox_id: @conversation.inbox_id,
      flow_id: @execution.chatflow_id,
      contact: {
        name: @conversation.contact&.name,
        phone_number: @conversation.contact&.phone_number
      }
    }
  end

  def simulation
    Chatflow::Simulator.current
  end

  def simulated(event, result = :wait)
    simulation.event(event, node: @node)
    result
  end
end
