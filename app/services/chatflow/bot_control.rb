# Pausar / retomar o robô numa conversa.
#
# Pausa quando um atendente responde no meio de um fluxo (ou alguém clica em
# "Pausar robô"): a execução fica `paused` na etapa onde estava e nenhum
# gatilho novo começa nesta conversa. "Retomar robô" devolve a execução à
# espera em que ela estava — inclusive a de uma Espera cujo relógio já venceu,
# que o scanner solta no minuto seguinte.
#
# A pausa automática some sozinha quando a conversa é resolvida ou depois de
# AUTO_PAUSE_TTL: a conta 5 tem uma conversa por contato para sempre, e uma
# pausa eterna mataria o aniversário e o pós-atendimento dessa cliente.
class Chatflow::BotControl
  FLAG = 'chatflow_paused'.freeze
  AUTO_PAUSE_TTL = 24.hours

  def self.paused?(conversation)
    flag = conversation.additional_attributes.to_h[FLAG]
    return false if flag.blank?
    return true if flag['until'].blank?

    Time.zone.parse(flag['until'].to_s)&.future? || false
  end

  # Um atendente respondeu. Só pausa quando há fluxo vivo e o fluxo pede isso.
  def self.agent_replied(conversation, user)
    execution = ChatflowExecution.live.find_by(conversation_id: conversation.id)
    return if execution.nil? || !execution.chatflow.pause_on_agent_reply?

    new(conversation).pause!(by: user, reason: 'agent_reply', expires_in: AUTO_PAUSE_TTL)
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def pause!(by: nil, reason: 'manual', expires_in: nil)
    execution = ChatflowExecution.live.find_by(conversation_id: @conversation.id)
    if execution
      paused_from = execution.status
      execution.update!(status: :paused, context: execution.context.merge('paused_from' => paused_from))
    end
    write_flag('at' => Time.current.iso8601, 'by' => by&.id, 'by_name' => by&.name, 'reason' => reason,
               'until' => expires_in&.from_now&.iso8601)
    execution
  end

  def resume!
    write_flag(nil)
    execution = paused_execution
    return if execution.nil?

    # Pausada no meio da corrida (sem etapa de espera): recomeça da etapa atual.
    if execution.context['paused_from'] == 'active' || execution.current_node.blank?
      execution.update!(status: :active)
      return Chatflow::EngineService.new(nil, conversation: @conversation).send(:run_chain, execution, execution.current_node)
    end
    execution.update!(status: :waiting_input)
    execution
  rescue ActiveRecord::RecordNotUnique
    # Um fluxo novo já começou nesta conversa: a pausada fica como interrompida.
    execution.update_columns(status: ChatflowExecution.statuses[:aborted]) # rubocop:disable Rails/SkipsModelValidations
    nil
  end

  # Resolvida: a pausa automática e a execução pausada perdem o sentido.
  def clear!
    write_flag(nil) if @conversation.additional_attributes.to_h[FLAG].present?
    paused_execution&.update!(status: :aborted)
  end

  def paused_execution
    ChatflowExecution.status_paused.where(conversation_id: @conversation.id).order(:id).last
  end

  def state
    flag = @conversation.additional_attributes.to_h[FLAG]
    execution = ChatflowExecution.where(conversation_id: @conversation.id)
                                 .where(status: %i[active waiting_input paused]).order(:id).last
    {
      paused: self.class.paused?(@conversation),
      paused_by: flag&.dig('by_name'),
      paused_reason: flag&.dig('reason'),
      paused_until: flag&.dig('until'),
      execution: execution && execution_payload(execution)
    }
  end

  private

  def execution_payload(execution)
    node = execution.current_node
    {
      id: execution.id, status: execution.status, chatflow_id: execution.chatflow_id,
      chatflow_name: execution.chatflow.name, node_name: node&.name.presence, node_kind: node&.kind,
      resume_at: execution.resume_at&.iso8601
    }
  end

  # Gravado direto na coluna: o additional_attributes não entra no
  # conversation.updated (só o idioma entra), então não acorda listener nenhum.
  def write_flag(value)
    attrs = @conversation.additional_attributes.to_h
    attrs = value.nil? ? attrs.except(FLAG) : attrs.merge(FLAG => value.compact)
    @conversation.update!(additional_attributes: attrs)
  end
end
