# Os esquemas das ferramentas do Guia.
#
# Nomes em português porque a conversa é, e um modelo escrevendo pt-BR alcança
# `fila_de_conversas` com mais segurança do que `conversation_queue`.
#
# Descrição é contrato: é por ela que o modelo decide QUANDO chamar. Onde ela
# for vaga, ele chama à toa e cada chamada à toa é uma iteração paga.
class Ai::Wiki::ToolDefinitions
  def self.all(can_scan:)
    defs = [queue_tool, findings_tool, inboxes_tool]
    defs << scan_tool if can_scan
    defs
  end

  def self.queue_tool
    tool(
      'fila_de_conversas',
      'Números da fila AGORA: quantas conversas abertas, quantas sem primeira resposta, ' \
      'quantas sem responsável e quantas pendentes. Use quando perguntarem sobre o volume ' \
      'de atendimento, fila, backlog ou "quantas conversas".'
    )
  end

  def self.findings_tool
    tool(
      'analise_das_conversas',
      'O que a última análise do Gerente encontrou de errado nas conversas: total por ' \
      'gravidade e os casos mais urgentes, com a data em que a análise rodou. ' \
      'Use para "o que está grave", "o que preciso olhar", "tem algo errado no atendimento". ' \
      'Se a resposta vier com analise_desatualizada, DIGA a data e ofereça rodar uma nova.'
    )
  end

  def self.inboxes_tool
    tool(
      'estado_das_caixas',
      'As caixas de entrada da conta, o canal de cada uma e quais precisam ser reconectadas. ' \
      'Use para "meu WhatsApp caiu", "minhas caixas estão conectadas", "quais canais eu tenho".'
    )
  end

  # A única que gasta: ela chama modelo uma vez por conversa lida. Por isso a
  # descrição exige confirmação explícita, no mesmo espírito da ferramenta de
  # agendamento do belezaki — o modelo não pode gastar o dinheiro do operador
  # porque achou que seria útil.
  def self.scan_tool
    tool(
      'rodar_analise',
      'Dispara uma análise NOVA das conversas. GASTA CRÉDITO da conta. ' \
      'Só chame depois que a pessoa disser SIM explicitamente e escolher a janela. ' \
      'Antes de chamar, pergunte: "24 horas, 3 dias, 7 dias ou 30 dias?". ' \
      'Nunca chame para responder uma pergunta que analise_das_conversas já responde.',
      {
        janela_horas: {
          type: 'integer',
          description: '24 para um dia, 72 para três dias, 168 para uma semana, 720 para um mês'
        }
      },
      %w[janela_horas]
    )
  end

  def self.tool(name, description, properties = {}, required = [])
    {
      name: name,
      description: description,
      input_schema: { type: 'object', properties: properties, required: required }
    }
  end
end
