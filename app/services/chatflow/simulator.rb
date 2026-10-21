# Simulador do editor: roda o fluxo de verdade (o mesmo motor, as mesmas
# validações, condições e saídas) sem que NADA saia da conta.
#
# Como: tudo acontece dentro de uma transação que é desfeita no fim. Contato,
# conversa, mensagens da "cliente" e a execução existem só durante a simulação;
# como nada é confirmado no banco, nenhum after_commit roda — nenhum listener,
# webhook da caixa ou envio para a WAHA. E as mensagens do robô nem chegam a
# ser criadas: o NodeRunnerService entrega o texto para o roteiro (#bot_message).
# Webhook e formulário do WhatsApp são pulados e anotados no roteiro.
#
# Sem estado entre chamadas: o editor manda as respostas da cliente desde o
# começo e o simulador reencena tudo. Esperas e "Digitando…" passam na hora
# (anotadas como evento). O sorteio do A/B usa a semente que o editor guarda,
# para a mesma conversa simulada sair sempre pelo mesmo ramo.
class Chatflow::Simulator
  MAX_INPUTS = 30
  MAX_FAST_FORWARDS = 10

  attr_reader :rng

  def self.current
    Thread.current[:chatflow_simulator]
  end

  def initialize(chatflow, inputs: [], seed: nil, contact: {})
    @chatflow = chatflow
    @account = chatflow.account
    @inputs = Array(inputs).map(&:to_s).first(MAX_INPUTS)
    @rng = Random.new(seed.presence&.to_i || Random.new_seed)
    @contact_params = contact.to_h
    @transcript = []
  end

  def perform
    result = nil
    ActiveRecord::Base.transaction do
      Thread.current[:chatflow_simulator] = self
      result = simulate
      raise ActiveRecord::Rollback
    end
    result
  ensure
    Thread.current[:chatflow_simulator] = nil
  end

  def bot_message(text, node:, attachment: false)
    @transcript << { type: 'bot', text: rendered(text), node_id: node.id, attachment: attachment }
    nil
  end

  def event(name, node: nil, detail: nil)
    @transcript << { type: 'event', event: name.to_s, node_id: node&.id, detail: detail }.compact
  end

  private

  def simulate
    return { error: 'no_start_node', transcript: [] } if @chatflow.start_node.blank?

    inbox = @chatflow.inbox || @account.inboxes.order(:id).first
    return { error: 'no_inbox', transcript: [] } if inbox.blank?

    @conversation = build_conversation(inbox)
    Chatflow::EngineService.new(nil, conversation: @conversation).start(@chatflow)
    fast_forward
    @inputs.each { |text| customer_says(text) }
    summary
  end

  # O mesmo Liquid que a mensagem de verdade passa ao ser criada ({{ contact.name }}…).
  def rendered(text)
    message = Message.new(account: @account, inbox: @conversation.inbox, conversation: @conversation,
                          message_type: :outgoing, content: text.to_s)
    message.send(:process_liquid_in_content)
    message.content.to_s
  end

  def build_conversation(inbox)
    contact = @account.contacts.create!(
      name: @contact_params['name'].presence || I18n.t('chatflow.simulator.contact_name'),
      custom_attributes: @contact_params['custom_attributes'].to_h
    )
    contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: "simulador-#{SecureRandom.hex(6)}")
    Conversation.create!(account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def customer_says(text)
    @transcript << { type: 'user', text: text }
    unless live_execution
      event(:ended)
      return
    end

    message = @conversation.messages.create!(account: @account, inbox: @conversation.inbox, message_type: :incoming,
                                             content: text, sender: @conversation.contact)
    Chatflow::EngineService.new(message).perform
    fast_forward
  end

  # Esperas e "Digitando…" passam na hora, anotadas no roteiro.
  def fast_forward
    MAX_FAST_FORWARDS.times do
      execution = live_execution
      break unless execution&.status_waiting_input? && execution.resume_at

      node = execution.current_node
      event(node&.kind_typing? ? :typed : :waited, node: node, detail: execution.resume_at.iso8601)
      execution.update!(resume_at: Time.current)
      Chatflow::EngineService.resume(execution)
    end
  end

  def live_execution
    ChatflowExecution.live.find_by(conversation_id: @conversation.id)
  end

  def summary
    executions = ChatflowExecution.where(conversation_id: @conversation.id).order(:id).to_a
    current = executions.last
    {
      transcript: @transcript,
      finished: live_execution.nil?,
      current_node_id: current&.live? ? current.current_node_id : nil,
      labels: @conversation.reload.label_list.to_a
    }.merge(execution_summary(executions))
  end

  def execution_summary(executions)
    {
      visited_node_ids: executions.select { |e| e.chatflow_id == @chatflow.id }.flat_map(&:visited_node_ids).uniq,
      answers: executions.map { |e| e.context['answers'].to_h }.reduce({}, :merge),
      selections: executions.flat_map { |e| Array(e.context['selections']) }
    }
  end
end
