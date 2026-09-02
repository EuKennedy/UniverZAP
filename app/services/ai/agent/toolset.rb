# As ferramentas de um agente, montadas uma vez e usadas por quem precisar.
#
# ## Por que existe
#
# A composição vivia dentro do AutopilotReplyService, então só o autopiloto
# tinha ferramenta. O copiloto do widget chamava Ai::ClaudeService#chat direto,
# sem `tools:` e sem loop — e o atendente via o mesmo agente que monta carrinho
# e consulta rastreio na conversa com o cliente ficar completamente cego quando
# ele abria o widget para pedir ajuda. Duas composições diferentes divergiriam;
# uma composição em dois lugares não.
#
# ## A conversa é opcional, e isso muda o que dá para oferecer
#
# Ferramenta customizada (carrinho, rastreio, integração do tenant) só precisa
# do agente. Agenda precisa de contato e de escopo: o belezaki usa o telefone do
# Contato para escrever e o id da conversa como chave de idempotência, e o
# Google precisa do contato para saber em nome de quem marcar.
#
# Uma thread do widget pode não ter conversa nenhuma. Nesse caso as ferramentas
# de agenda ficam de fora em vez de serem montadas com contato nulo — um
# agendamento sem telefone é exatamente a falha que Ai::Belezaki::CustomerPhone
# documenta: agenda duplicada, confirmação morrendo em silêncio.
class Ai::Agent::Toolset
  def initialize(assistant:, conversation: nil)
    @assistant = assistant
    @conversation = conversation
  end

  # Um CompositeExecutor com tudo que este agente pode fazer agora.
  def executor
    @executor ||= Ai::Agent::CompositeExecutor.new(parts)
  end

  private

  def parts
    list = []
    list << [custom_tool_executor.definitions, custom_tool_executor] if custom_tools.any?
    list.concat(agenda_parts)
    list
  end

  # Exatamente UMA agenda, decidida pelo modelo e não por dois ramos
  # respondendo sim. Os dois provedores declaram cinco nomes em comum
  # (consultar_horarios, agendar, meus_agendamentos, remarcar, desmarcar), e a
  # Anthropic recusa a requisição inteira com 400 quando um nome se repete — um
  # agente com as duas para de responder para todo mundo, na hora.
  def agenda_parts
    return [] if @conversation.nil?

    case @assistant.agenda_provider
    when :google
      calendar_definitions.present? ? [[calendar_definitions, calendar_executor]] : []
    when :belezaki
      [[belezaki_definitions, belezaki_executor]]
    else
      []
    end
  end

  def custom_tools
    @custom_tools ||= @assistant.custom_tools.enabled.to_a
  end

  def custom_tool_executor
    @custom_tool_executor ||= Ai::CustomToolExecutor.new(custom_tools)
  end

  def calendar_definitions
    return @calendar_definitions if defined?(@calendar_definitions)

    @calendar_definitions = Ai::Calendar::ToolDefinitions.for(@assistant)
  end

  def calendar_executor
    @calendar_executor ||= Ai::Calendar::SchedulingTools.new(
      assistant: @assistant, contact: @conversation.contact, conversation: @conversation
    )
  end

  def belezaki_connection
    return @belezaki_connection if defined?(@belezaki_connection)

    connection = @assistant.belezaki_connection
    @belezaki_connection = connection&.active? ? connection : nil
  end

  def belezaki_definitions
    Ai::Belezaki::SchedulingTools.definitions(include_booking: true)
  end

  # O id do salão vem da CONEXÃO e não de resolver a conta de novo: congelá-lo
  # é o que impede um religamento de mover um agente vivo para a agenda de
  # outro salão no meio de uma conversa.
  def belezaki_executor
    @belezaki_executor ||= Ai::Belezaki::SchedulingTools.new(
      Ai::Belezaki::AgentClient.new(external_id: belezaki_connection.external_id),
      scope: "conv-#{@conversation.id}",
      contact: { name: @conversation.contact&.name, phone: @conversation.contact&.phone_number },
      connection: belezaki_connection
    )
  end
end
