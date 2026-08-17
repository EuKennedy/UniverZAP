# Uma mudança que o Gerente propõe para um agente, com a evidência que a
# sustenta, esperando decisão humana.
#
# Nasce `pending` e nunca sai daí sozinha. As duas alavancas são deliberadamente
# poucas: mexer na memória (Ai::Training) ou propor uma candidata de prompt que
# entra na disputa A/B que já existe. Ferramenta e configuração do agente ficam
# fora do alcance, porque uma sugestão errada nessas duas não é uma resposta
# ruim, é um agente que para de funcionar.
class Ai::Manager::Suggestion < ApplicationRecord
  self.table_name = 'ai_manager_suggestions'

  belongs_to :account
  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :ai_manager_run, class_name: 'Ai::Manager::Run'
  belongs_to :ai_prompt_version, class_name: 'Ai::PromptVersion', optional: true
  belongs_to :ai_training, class_name: 'Ai::Training', optional: true

  # `inconclusive` não é um estado que um humano escolhe: é onde uma sugestão
  # aplicada para quando a medição posterior não conseguiu dizer se funcionou,
  # normalmente porque o agente não teve conversa suficiente depois da mudança.
  # Sem ele, uma medição vazia viraria "não funcionou", que é uma conclusão que
  # o dado não autoriza.
  STATUSES = %w[pending approved dismissed applied inconclusive].freeze
  # Ainda esperando decisão. É o conjunto que a fila mostra e o ÚNICO de onde uma
  # sugestão pode virar mudança de verdade: fora dele estão `dismissed` (o
  # operador disse não), `applied` (já virou) e `inconclusive`, que é onde uma
  # sugestão JÁ APLICADA para quando a medição não conclui nada. Nomeado aqui
  # porque o Applier precisa da mesma lista, e as duas discordarem seria uma
  # sugestão dispensada virando documento.
  OPEN_STATUSES = %w[pending approved].freeze
  SEVERITIES = %w[critical high normal].freeze
  TARGETS = %w[training prompt_version].freeze

  validates :check_key, :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :target, inclusion: { in: TARGETS }

  scope :pending, -> { where(status: 'pending') }
  scope :open_items, -> { where(status: OPEN_STATUSES) }
  # Ordem de severidade primeiro, e não data: quem abre a tela tem cinco minutos
  # e o horário prometido errado precisa ser lido antes do agente que anda
  # prolixo.
  scope :by_urgency, lambda {
    order(Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END"), created_at: :desc)
  }

  def applied?
    status == 'applied'
  end

  # Ainda não virou nada, e ainda pode virar. As duas metades importam: o estado
  # diz que ninguém decidiu, e as duas alavancas vazias dizem que nada foi
  # escrito no agente. Uma sugestão que já produziu documento ou candidata não
  # pode produzir a segunda, aconteça o que acontecer com a coluna de status.
  def open?
    OPEN_STATUSES.include?(status) && ai_training_id.nil? && ai_prompt_version_id.nil?
  end

  def decided?
    status != 'pending'
  end

  def push_event_data
    {
      id: id, ai_assistant_id: ai_assistant_id, agent_name: ai_assistant&.name,
      check_key: check_key, title: title, rationale: rationale, severity: severity,
      evidence: evidence, target: target, proposed: proposed, status: status,
      applied_as: applied_as, dismissed_reason: dismissed_reason, outcome: outcome,
      created_at: created_at.to_i
    }
  end

  # O que a aprovação virou de fato, para a tela poder linkar em vez de dizer
  # apenas "aplicada" e deixar o operador procurar.
  def applied_as
    return { type: 'training', id: ai_training_id } if ai_training_id.present?
    return { type: 'prompt_version', id: ai_prompt_version_id } if ai_prompt_version_id.present?

    nil
  end
end
