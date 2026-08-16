# frozen_string_literal: true

# Quais arquivos são código UniverZAP, e não do fork.
#
# Existe como arquivo próprio, fora de spec/ e fora de bin/, porque duas coisas
# muito distantes precisam da mesma resposta: o SimpleCov, que roda dentro do
# processo do RSpec e agrupa o relatório, e o portão de cobertura, que roda em
# outro job da CI sobre os resultados já colados, sem Rails carregado. Se cada
# um carregasse a própria lista, o relatório mostraria um conjunto e o portão
# exigiria piso de outro, e o desencontro só apareceria no dia em que alguém
# fosse investigar por que o número não bate.
#
# O critério para entrar aqui é simples e verificável: diretórios que este
# projeto criou. Nada de arquivo do Chatwoot que a gente editou de raspão, que
# levaria a exigir piso sobre código que não escrevemos.
module UniverzapCoverage
  GROUPS = {
    'Athenas (IA)' => [
      'app/services/ai/',
      'app/models/ai/',
      'app/controllers/api/v1/accounts/ai/',
      'app/jobs/ai/'
    ],
    'WhatsApp & WAHA' => [
      'app/services/whatsapp/',
      'app/controllers/api/v1/accounts/whatsapp/',
      'app/controllers/webhooks/waha_controller.rb',
      'app/jobs/webhooks/waha_events_job.rb'
    ],
    'Kanban & Funis' => [
      'app/services/kanban/',
      'app/controllers/api/v1/accounts/funnels_controller.rb',
      'app/controllers/api/v1/accounts/funnel_stages_controller.rb',
      'app/controllers/api/v1/accounts/funnel_custom_fields_controller.rb'
    ],
    'Disparos' => [
      'app/services/broadcasts/',
      'app/jobs/broadcasts/',
      'app/models/broadcast.rb',
      'app/models/broadcast_recipient.rb',
      'app/controllers/api/v1/accounts/broadcasts_controller.rb'
    ],
    'Chatflow' => [
      'app/services/chatflow/',
      'app/controllers/api/v1/accounts/chatflows/',
      'app/controllers/api/v1/accounts/chatflows_controller.rb',
      'app/controllers/api/v1/accounts/chatflow_nodes_controller.rb',
      'app/controllers/api/v1/accounts/chatflow_edges_controller.rb'
    ]
  }.freeze

  ALL_PATHS = GROUPS.values.flatten.freeze

  # Comparação por sufixo e não por caminho absoluto, porque o SimpleCov grava
  # o caminho da máquina que rodou (/home/runner/work/... na CI, C:/Users/...
  # aqui) e o portão lê esse arquivo em outra máquina ainda.
  def self.owned_by?(filename, paths = ALL_PATHS)
    normalised = filename.to_s.tr('\\', '/')
    paths.any? { |path| normalised.include?("/#{path}") || normalised.start_with?(path) }
  end

  def self.group_for(filename)
    GROUPS.find { |_name, paths| owned_by?(filename, paths) }&.first
  end
end
