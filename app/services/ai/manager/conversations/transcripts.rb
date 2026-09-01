# As últimas mensagens de várias conversas, numa consulta só.
#
# Uma função de janela e não um laço com uma consulta por conversa: sessenta
# conversas viram uma ida ao banco em vez de sessenta, e o custo da leitura
# passa a ser o do modelo e não o do Postgres.
#
# O corte é pelas ÚLTIMAS mensagens e não pelas primeiras. O que decide se uma
# compra travou está sempre no fim do diálogo, e mandar o começo de uma conversa
# de oitenta mensagens é pagar por contexto que já foi resolvido.
class Ai::Manager::Conversations::Transcripts
  # Doze mensagens é o que cobre a última rodada de ida e volta com folga.
  # Acima disso o custo cresce e a conclusão não muda, porque o modelo passa a
  # reler o que já estava resolvido.
  DEPTH = 12
  # Áudio transcrito e mensagem longa colada existem, e uma delas sozinha pode
  # dominar a janela inteira. O corte por mensagem protege as outras onze.
  MESSAGE_MAX_CHARS = 320

  Line = Struct.new(:incoming, :text, :at, keyword_init: true)

  def initialize(conversation_ids:, depth: DEPTH)
    @ids = Array(conversation_ids).uniq
    @depth = depth
  end

  # conversation_id => [Line, ...] em ordem cronológica, do mais antigo para o
  # mais novo, que é como uma pessoa lê.
  def all
    @all ||= rows.group_by { |row| row['conversation_id'] }
                 .transform_values { |group| group.map { |row| line(row) } }
  end

  private

  def line(row)
    Line.new(
      incoming: row['message_type'].to_i == Message.message_types[:incoming],
      text: row['content'].to_s.strip.truncate(MESSAGE_MAX_CHARS),
      at: row['created_at']
    )
  end

  def rows
    return [] if @ids.empty?

    Message.connection.select_all(Message.sanitize_sql_array([SQL, @ids, @depth])).to_a
  end

  SQL = <<~SQL.squish.freeze
    SELECT conversation_id, message_type, content, created_at FROM (
      SELECT conversation_id, message_type, content, created_at,
             ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY created_at DESC) AS rn
      FROM messages
      WHERE conversation_id IN (?)
        AND private = false
        AND message_type IN (0, 1)
        AND content IS NOT NULL
        AND content <> ''
    ) recentes
    WHERE rn <= ?
    ORDER BY conversation_id, created_at ASC
  SQL
end
