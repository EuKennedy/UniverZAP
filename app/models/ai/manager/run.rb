# Uma varredura do Gerente sobre os agentes de uma conta.
#
# Guarda a janela analisada e o tamanho da amostra junto do resultado, e não só
# o resultado: a mesma conclusão tirada de 400 conversas e de 6 vale coisas
# diferentes, e sem os dois números ao lado ninguém consegue dizer qual das duas
# está lendo.
class Ai::Manager::Run < ApplicationRecord
  self.table_name = 'ai_manager_runs'

  belongs_to :account
  has_many :suggestions, class_name: 'Ai::Manager::Suggestion', foreign_key: :ai_manager_run_id,
                         inverse_of: :ai_manager_run, dependent: :destroy

  STATUSES = %w[running done failed].freeze
  TRIGGERS = %w[schedule manual].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :triggered_by, inclusion: { in: TRIGGERS }

  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: 'done') }

  # A rodada terminou certa e mesmo assim não concluiu nada, porque a amostra
  # era pequena demais. É um resultado, não uma falha, e por isso mora no resumo
  # em vez de virar `failed`: uma conta nova precisa ver "faltam 14 conversas" e
  # não uma tela vermelha dizendo que algo quebrou.
  def insufficient_data?
    summary.to_h['insufficient_data'].present?
  end

  def push_event_data
    {
      id: id, status: status, triggered_by: triggered_by,
      conversations_analysed: conversations_analysed,
      cost_cents_brl: cost_cents_brl,
      suggestions_created: summary.to_h['suggestions_created'].to_i,
      insufficient_data: insufficient_data?,
      started_at: started_at&.to_i, finished_at: finished_at&.to_i,
      created_at: created_at.to_i
    }
  end
end
