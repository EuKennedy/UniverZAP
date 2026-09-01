# A leitura da tela: os achados já gravados, fatiados pelos filtros, sem gastar
# um token para reexibir o que já foi analisado.
#
# Esta é a metade da feature que o operador usa todo dia. A varredura roda
# quando ele clica; isto aqui roda toda vez que ele muda um filtro, e por isso
# não pode chamar modelo nenhum nem crescer com o tamanho da lista.
#
# O trabalho menos óbvio daqui é não deixar o painel mentir. Um achado de terça
# dizendo "cliente esperando há 30h" continua no banco depois que alguém
# respondeu na quarta, e mostrá-lo igual seria mandar o operador atender de novo
# quem já foi atendido. Uma consulta agregada resolve isso para a página inteira
# e empurra os resolvidos para o fim, sem apagar nada: o histórico continua
# gravado, que é o que foi pedido.
class Ai::Manager::Conversations::Listing
  # Janelas que a tela oferece, em dias. `nil` é tudo que está gravado.
  WINDOWS = [1, 3, 7, 30].freeze

  # Teto de cartões por resposta. Acima disso ninguém lê, e o que importa está
  # nos primeiros, que vêm por gravidade.
  MAX = 200

  def initialize(account:, days: nil, author: nil, case_key: nil, limit: MAX)
    @account = account
    @days = WINDOWS.include?(days.to_i) ? days.to_i : nil
    @author = author
    @case_key = case_key
    @limit = limit
  end

  def payload
    {
      findings: cards,
      counts: counts,
      filters: { days: @days, author: @author.presence, case_key: @case_key.presence },
      last_scan: last_scan&.push_event_data,
      windows: WINDOWS,
      cases: Ai::Manager::Conversations::Cases::ALL.map { |key, spec| { key: key, title: spec[:title] } }
    }
  end

  private

  def filtered
    @filtered ||= Ai::Manager::ConversationFinding.where(account_id: @account.id)
                                                  .occurred_since(@days&.days&.ago)
                                                  .by_author(@author)
                                                  .by_case(@case_key)
  end

  def records
    @records ||= filtered.by_urgency.limit(@limit).to_a
  end

  # Quem já foi respondido vai para o fim, mantendo a ordem de urgência dentro
  # de cada bloco. `partition` e não uma segunda consulta: a informação que
  # decide isto não está na tabela de achados, e nem deve estar, porque mudaria
  # sozinha toda vez que alguém digitasse na conversa.
  def cards
    pending, answered = records.partition { |record| !answered?(record) }
    (pending + answered).map { |record| card(record) }
  end

  def card(record)
    record.push_event_data.merge(
      contact_name: contact_names[record.contact_id],
      answered_after: answered?(record)
    )
  end

  def answered?(record)
    replied = last_outgoing[record.conversation_id]
    replied.present? && record.occurred_at.present? && replied > record.occurred_at
  end

  # Uma consulta agregada para a página inteira. A alternativa seria perguntar
  # "já responderam?" por cartão, que é como um painel de duzentas linhas vira
  # duzentas consultas e o operador culpa a internet.
  def last_outgoing
    @last_outgoing ||= begin
      ids = records.map(&:conversation_id).uniq
      ids.empty? ? {} : Message.where(conversation_id: ids, private: false,
                                      message_type: Message.message_types[:outgoing])
                               .group(:conversation_id).maximum(:created_at)
    end
  end

  def contact_names
    @contact_names ||= begin
      ids = records.filter_map(&:contact_id).uniq
      ids.empty? ? {} : Contact.where(id: ids).pluck(:id, :name).to_h
    end
  end

  # Contados sobre o conjunto FILTRADO e não sobre a página: o operador precisa
  # saber que existem 40 críticos mesmo quando o teto mostrou 200 cartões.
  def counts
    {
      total: filtered.count,
      by_severity: filtered.group(:severity).count,
      by_author: filtered.group(:author).count,
      by_case: filtered.group(:case_key).count
    }
  end

  def last_scan
    @last_scan ||= Ai::Manager::ConversationScan.where(account_id: @account.id).recent.first
  end
end
