# O catálogo do moderador: tudo que ele sabe enxergar numa conversa.
#
# Dividido por CUSTO e não por tema, porque é o custo que decide o desenho. Os
# casos de `TRIAGE` saem de SQL puro e não gastam um token sequer: "a última
# mensagem é do cliente e ninguém respondeu depois" é uma consulta, não uma
# opinião, e pagar um modelo para concluir isso seria queimar dinheiro para
# obter uma resposta pior. Os de `READING` exigem entender o que foi dito
# ("quis comprar", "ficou irritada"), e só esses chegam ao modelo.
#
# A consequência prática é a que foi pedida: numa conta com 200 conversas em
# 24h, a triagem varre as 200 de graça e a leitura recebe as poucas dezenas que
# sobraram. É isso que torna a janela de 30 dias tão barata quanto a de um dia.
module Ai::Manager::Conversations::Cases
  # Achados que saem de consulta, sempre grátis.
  TRIAGE = {
    'cliente_esperando' => {
      title: 'Cliente esperando resposta',
      # A severidade deste é a única calculada, porque a gravidade é o relógio:
      # o mesmo silêncio vale um aviso às 6 horas e uma emergência às 30.
      severity: :by_wait,
      what: 'A última mensagem é do cliente e ninguém respondeu depois dela.'
    }.freeze,
    'agente_repetiu' => {
      title: 'O agente ficou repetindo a mesma resposta',
      severity: 'high',
      what: 'O agente entregou a mesma resposta mais de uma vez na conversa, sinal de que travou em vez de avançar.'
    }.freeze,
    'resposta_marcada' => {
      title: 'O agente disse algo que os guardrails marcaram',
      severity: 'high',
      what: 'Uma resposta desta conversa levantou bandeira de preço inventado, promessa solta ou informação sem lastro.'
    }.freeze
  }.freeze

  # Achados que exigem ler o que foi dito. Só as conversas que a triagem
  # levantou chegam aqui, e o modelo devolve no máximo um caso de cada.
  READING = {
    'compra_travada' => {
      title: 'Cliente quis comprar e a conversa parou',
      severity: 'critical',
      what: 'O cliente demonstrou intenção clara de comprar ou agendar algo específico, e a conversa morreu sem conclusão.'
    }.freeze,
    'pedido_de_humano' => {
      title: 'Cliente pediu para falar com uma pessoa',
      severity: 'critical',
      what: 'O cliente pediu atendimento humano, e ninguém assumiu a conversa depois disso.'
    }.freeze,
    'pergunta_sem_resposta' => {
      title: 'Cliente perguntou e não foi respondido',
      severity: 'high',
      what: 'O cliente fez uma pergunta concreta e a resposta seguinte não respondeu o que foi perguntado.'
    }.freeze,
    'cliente_insatisfeito' => {
      title: 'Cliente demonstrou insatisfação',
      severity: 'high',
      what: 'O cliente reclamou, cobrou ou demonstrou irritação com o atendimento, o prazo ou o produto.'
    }.freeze
  }.freeze

  ALL = TRIAGE.merge(READING).freeze
  READING_KEYS = READING.keys.freeze

  # Ordem de gravidade, e o número que ordena a lista. Fica aqui e não no front
  # porque é a mesma régua que o `ORDER BY` do banco usa: a tela e a consulta
  # discordarem sobre o que é grave é como uma lista "por urgência" acaba
  # mostrando o irrelevante em cima.
  SEVERITIES = %w[critical high medium low].freeze
  SEVERITY_RANK = { 'critical' => 0, 'high' => 1, 'medium' => 2, 'low' => 3 }.freeze

  # As faixas do relógio, em horas. Seis horas é o piso porque abaixo disso o
  # silêncio ainda é atendimento normal, e um painel que acusa a conversa de
  # vinte minutos atrás é um painel que ninguém consegue usar.
  WAIT_FLOOR_HOURS = 6
  WAIT_HIGH_HOURS = 12
  WAIT_CRITICAL_HOURS = 24

  module_function

  def known?(key)
    ALL.key?(key.to_s)
  end

  def title_for(key)
    ALL.dig(key.to_s, :title).to_s
  end

  def what_for(key)
    ALL.dig(key.to_s, :what).to_s
  end

  def reading?(key)
    READING.key?(key.to_s)
  end

  def severity_for(key, hours: 0)
    declared = ALL.dig(key.to_s, :severity)
    return declared if declared.is_a?(String)

    severity_by_wait(hours)
  end

  def severity_by_wait(hours)
    return 'critical' if hours >= WAIT_CRITICAL_HOURS
    return 'high' if hours >= WAIT_HIGH_HOURS

    'medium'
  end

  # O que o modelo pode devolver. Qualquer chave fora desta lista é descartada
  # na leitura: um modelo que inventa uma categoria nova escreveria um cartão
  # que a tela não sabe rotular nem traduzir.
  def reading_catalogue
    READING.map { |key, spec| "- #{key}: #{spec[:what]}" }.join("\n")
  end
end
