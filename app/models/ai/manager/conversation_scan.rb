# Uma leitura de conversas: quando rodou, que janela pediu, quanto custou e o
# que ficou de fora.
#
# Existe para a tela poder ser honesta. Sem esta linha, um painel com doze
# cartões parece a operação inteira, quando pode ser o teto de leitura tendo
# cortado noventa conversas que ninguém olhou. O número que ficou de fora vale
# mais que os doze que apareceram, porque é ele que diz se dá para confiar no
# vazio do resto.
class Ai::Manager::ConversationScan < ApplicationRecord
  self.table_name = 'ai_manager_conversation_scans'

  belongs_to :account
  has_many :findings, class_name: 'Ai::Manager::ConversationFinding',
                      foreign_key: :scan_id, dependent: :nullify, inverse_of: false

  STATUSES = %w[running done failed].freeze

  # As janelas que a tela oferece. Fechada e não livre: um campo de horas aberto
  # deixaria alguém pedir um ano e derrubar a varredura no timeout, e as quatro
  # cobrem o que uma operação de verdade pergunta (hoje, esta semana, este mês).
  WINDOWS = [24, 72, 168, 720].freeze
  DEFAULT_WINDOW = 24

  validates :status, inclusion: { in: STATUSES }
  validates :window_hours, inclusion: { in: WINDOWS }

  scope :recent, -> { order(created_at: :desc) }

  def self.window_for(value)
    hours = value.to_i
    WINDOWS.include?(hours) ? hours : DEFAULT_WINDOW
  end

  def running?
    status == 'running'
  end

  def cost_brl
    (cost_cents_brl.to_i / 100.0).round(2)
  end

  # Quantas conversas a triagem levantou e o teto de leitura deixou para trás.
  def not_read
    [summary['candidates'].to_i - conversations_read.to_i, 0].max
  end

  def push_event_data
    {
      id: id, status: status, window_hours: window_hours, started_at: started_at,
      finished_at: finished_at, conversations_scanned: conversations_scanned,
      conversations_read: conversations_read, not_read: not_read,
      findings_count: findings_count, cost_brl: cost_brl, summary: summary
    }
  end
end
