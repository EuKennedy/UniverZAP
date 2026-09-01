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

  # Sete dias e não vinte e quatro horas, e isto foi aprendido quebrando.
  #
  # A janela decide até onde a varredura enxerga mensagem. O caso mais
  # importante desta tela é "cliente sem resposta há mais de um dia", e a
  # mensagem dessa cliente tem, por definição, MAIS de um dia. Com janela de
  # 24h ela cai fora, e a varredura devolve vazio exatamente na situação que
  # ela existe para pegar.
  #
  # O custo não muda: quem cobra é a leitura por modelo, e ela para no teto de
  # Ai::Manager::Conversations::Reader::MAX_READ em qualquer janela. Alargar a
  # janela traz mais achados de graça e no máximo troca QUAIS conversas entram
  # no mesmo teto pago.
  DEFAULT_WINDOW = 168

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
