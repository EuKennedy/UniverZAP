# Um problema encontrado numa conversa, com o endereço para ir resolver.
#
# Não tem status, não tem aprovação e não tem botão de aplicar, e isso é a
# definição do objeto e não uma etapa que faltou. O que resolve um destes é
# alguém abrir a conversa e responder a pessoa, e no instante em que isso
# acontece o achado deixou de existir sozinho. Dar a ele um fluxo de decisão
# criaria uma segunda fila para o operador manter em dia depois de já ter
# resolvido o problema de verdade, e é assim que um painel útil vira burocracia.
#
# O que dá vida longa a ele é o índice único por (conta, conversa, caso): rodar
# a leitura de novo ATUALIZA o mesmo achado em vez de empilhar cópias. É o que
# permite a tela prometida: a leitura fica gravada e os filtros de dia fatiam o
# que já existe, sem gastar um token para reexibir o que já foi analisado.
class Ai::Manager::ConversationFinding < ApplicationRecord
  self.table_name = 'ai_manager_conversation_findings'

  belongs_to :account

  # Quem falou por último do nosso lado. `none` é ninguém: o cliente escreveu e
  # a conversa nunca teve resposta, que é o caso mais grave dos três.
  AUTHORS = %w[agent human none].freeze
  SOURCES = %w[triage reading].freeze

  validates :case_key, :title, :conversation_id, :occurred_at, :last_seen_at, presence: true
  validates :severity, inclusion: { in: Ai::Manager::Conversations::Cases::SEVERITIES }
  validates :author, inclusion: { in: AUTHORS }
  validates :source, inclusion: { in: SOURCES }

  # A ordem da tela, e a mesma que a consulta usa.
  #
  # Gravidade primeiro, depois dinheiro parado, e só então o relógio. E dentro
  # do relógio o MAIS ANTIGO na frente, que é o contrário do que uma lista de
  # notícias faria: aqui a linha mais velha é a pessoa que está esperando há
  # mais tempo, e empurrá-la para o fim é o mesmo que perdê-la de novo.
  SEVERITY_ORDER = Arel.sql(
    "CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END"
  )

  scope :by_urgency, -> { order(SEVERITY_ORDER, value_cents_brl: :desc, occurred_at: :asc) }
  scope :occurred_since, ->(time) { time.present? ? where(occurred_at: time..) : all }
  scope :by_author, ->(author) { author.to_s.in?(AUTHORS) ? where(author: author) : all }
  scope :by_case, ->(key) { key.present? ? where(case_key: key) : all }

  def value_brl
    (value_cents_brl.to_i / 100.0).round(2)
  end

  def waited_hours
    metadata['waited_hours'].presence || (waiting_since && ((Time.current - waiting_since) / 3600.0).round(1))
  end

  # `answered_after` NÃO sai daqui: é calculado em lote por
  # Ai::Manager::Conversations::Listing para a página inteira. Resolvê-lo aqui
  # custaria uma consulta por cartão, que é o jeito clássico de um painel de
  # quarenta linhas ficar lento sem ninguém entender por quê.
  def push_event_data
    {
      id: id, case_key: case_key, severity: severity, title: title, detail: detail,
      excerpt: excerpt, author: author, source: source, conversation_id: conversation_id,
      conversation_display_id: conversation_display_id, contact_id: contact_id,
      occurred_at: occurred_at, waiting_since: waiting_since, waited_hours: waited_hours,
      value_brl: value_brl, last_seen_at: last_seen_at, metadata: metadata
    }
  end
end
