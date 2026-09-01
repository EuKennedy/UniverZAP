# O retrato da janela numa consulta só: por conversa, quando o cliente falou
# pela última vez, quando alguém respondeu pela última vez, e quantas mensagens
# foram para cada lado.
#
# Uma consulta agregada e não N consultas por conversa, porque é daqui que sai
# TODA a triagem. Numa conta com duzentas conversas em 24h, a diferença entre
# esta classe e o laço ingênuo é entre um painel que abre em meio segundo e um
# que estoura o timeout do navegador no primeiro salão movimentado.
#
# `FILTER (WHERE ...)` e não cinco consultas com `WHERE` diferente: o Postgres
# varre o índice uma vez e devolve os cinco números juntos. O índice usado é
# index_messages_on_conversation_account_type_created, que já existe nesta base.
class Ai::Manager::Conversations::Activity
  # Teto de conversas examinadas por rodada. A ordenação é pela atividade mais
  # recente, então o corte descarta o mais frio, nunca o mais urgente. O número
  # que sobrou fica visível na tela: uma varredura que silenciosamente ignora
  # metade da operação é pior que uma que não roda.
  MAX_CONVERSATIONS = 500

  # Só o que uma pessoa mandou ou recebeu. `activity` é registro do sistema
  # ("fulano assumiu a conversa") e `private` é nota interna: contar as duas
  # como resposta faria uma conversa esquecida parecer atendida porque alguém
  # escreveu um bilhete que o cliente nunca viu.
  HUMAN_TYPES = [Message.message_types[:incoming], Message.message_types[:outgoing]].freeze

  Row = Struct.new(:conversation_id, :last_in, :last_out, :incoming, :outgoing, keyword_init: true) do
    # A definição de "esperando" desta base: existe fala do cliente e não existe
    # resposta depois dela. `last_out` anterior à janela ainda serve, porque uma
    # resposta de antes da última pergunta não é resposta àquela pergunta.
    def waiting?
      last_in.present? && (last_out.nil? || last_out < last_in)
    end

    def messages
      incoming.to_i + outgoing.to_i
    end

    def waited_hours(now)
      return 0.0 unless waiting?

      ((now - last_in) / 3600.0).round(1)
    end
  end

  def initialize(account:, since:)
    @account = account
    @since = since
  end

  # Hash de conversation_id para Row. Hash e não array porque todo consumidor
  # daqui pergunta "e a conversa tal?".
  def rows
    @rows ||= raw.to_h do |record|
      [record.conversation_id,
       Row.new(conversation_id: record.conversation_id, last_in: record.last_in, last_out: record.last_out,
               incoming: record.incoming.to_i, outgoing: record.outgoing.to_i)]
    end
  end

  private

  # Colunas APELIDADAS e lidas como atributos, e não um `pluck` com cinco
  # colunas dentro de um Arel.sql só. O `pluck` decide se devolve valores ou
  # tuplas pelo número de ARGUMENTOS que recebeu, não pelo de colunas que a SQL
  # tem, e o casting nesse caminho passa a depender do nome que o Postgres der
  # ao agregado. Lendo como atributo, `last_in` volta como Time e `incoming`
  # como inteiro, que é o contrato que Row promete.
  AGGREGATES = <<~SQL.squish.freeze
    messages.conversation_id,
    MAX(messages.created_at) FILTER (WHERE messages.message_type = 0) AS last_in,
    MAX(messages.created_at) FILTER (WHERE messages.message_type = 1) AS last_out,
    COUNT(*) FILTER (WHERE messages.message_type = 0) AS incoming,
    COUNT(*) FILTER (WHERE messages.message_type = 1) AS outgoing
  SQL

  def raw
    Message.where(account_id: @account.id, private: false, message_type: HUMAN_TYPES)
           .where(messages: { created_at: @since.. })
           .group('messages.conversation_id')
           .select(Arel.sql(AGGREGATES))
           # `reorder` e não `order`: Message carrega
           # `default_scope { order(created_at: :asc) }`, e essa ordenação herdada
           # é colada DEPOIS da minha, referenciando messages.created_at fora de
           # qualquer agregado. O Postgres recusa a consulta inteira com
           # GroupingError. `reorder` substitui em vez de acrescentar.
           .reorder(Arel.sql('MAX(messages.created_at) DESC'))
           .limit(MAX_CONVERSATIONS)
  end
end
