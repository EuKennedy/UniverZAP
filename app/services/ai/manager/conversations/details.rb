# Tudo que um cartão precisa mostrar, buscado em lote para o conjunto inteiro.
#
# Seis consultas para a página toda, e não seis por cartão. A tentação aqui é
# resolver cada campo dentro do laço que monta os achados, e é assim que um
# painel de quarenta cartões vira duzentas e quarenta consultas: rápido de
# escrever, inutilizável no primeiro salão movimentado.
#
# É também a fronteira do sandbox. As conversas do playground são conversas de
# verdade no banco, e um cartão dizendo "cliente esperando há 30h" sobre um
# teste que o próprio operador abandonou é exatamente o falso positivo que faz
# a aba perder credibilidade na primeira semana.
class Ai::Manager::Conversations::Details
  # O trecho é para reconhecer o caso de relance, não para reler a conversa. O
  # botão do cartão existe justamente para quem quer o texto inteiro.
  EXCERPT_MAX = 240

  Detail = Struct.new(:conversation_id, :display_id, :contact_id, :contact_name, :status,
                      :assignee_id, :excerpt, :author, :value_cents, :interest, :assistant_id,
                      keyword_init: true)

  def initialize(account:, conversation_ids:)
    @account = account
    @requested = Array(conversation_ids).uniq
  end

  # Só as que sobreviveram ao filtro de sandbox e ainda existem.
  def ids
    conversations.keys
  end

  def for(conversation_id)
    built[conversation_id]
  end

  private

  def built
    @built ||= conversations.transform_values { |row| build(row) }
  end

  def build(row)
    Detail.new(
      conversation_id: row.id, display_id: row.display_id, contact_id: row.contact_id,
      contact_name: contact_names[row.contact_id], status: row.status, assignee_id: row.assignee_id,
      excerpt: excerpts[row.id].to_s.strip.truncate(EXCERPT_MAX).presence,
      author: author_for(row), value_cents: lead_values.dig(row.id, :cents).to_i,
      interest: lead_values.dig(row.id, :interest), assistant_id: agent_replies[last_outgoing[row.id]]
    )
  end

  # Quem falou por último do nosso lado, que é o filtro pedido: às vezes o
  # operador quer olhar só o que o robô atendeu, às vezes só o que a equipe
  # deixou parado.
  #
  # Decidido pela ÚLTIMA mensagem enviada e não pelo responsável da conversa,
  # porque é a resposta que responde. Uma conversa atribuída a uma pessoa cuja
  # última fala saiu do agente é uma conversa que o agente estava conduzindo, e
  # contá-la como humana esconderia o robô de quem foi filtrar o robô.
  #
  # A prova de que a mensagem saiu do agente é a linha em ai_invocations que
  # aponta para ela, e não o `sender_type`: a convenção de remetente muda com o
  # canal, a linha do log não muda nunca.
  def author_for(row)
    outgoing_id = last_outgoing[row.id]
    return 'none' if outgoing_id.blank?

    agent_replies.key?(outgoing_id) ? 'agent' : 'human'
  end

  # `select` e não `pluck`: os cinco campos voltam como objeto, `status` já vem
  # como string do enum, e o construtor do cartão fica legível em vez de uma
  # tupla posicional que ninguém consegue reordenar sem quebrar.
  def conversations
    @conversations ||= @account.conversations.not_sandbox.where(id: @requested)
                               .select(:id, :display_id, :contact_id, :status, :assignee_id)
                               .index_by(&:id)
  end

  def contact_names
    @contact_names ||= begin
      contact_ids = conversations.values.filter_map(&:contact_id).uniq
      contact_ids.empty? ? {} : Contact.where(id: contact_ids).pluck(:id, :name).to_h
    end
  end

  # `DISTINCT ON` e não um `order` seguido de deduplicação em Ruby: sem isto a
  # consulta traz todas as mensagens da janela para a memória só para descartar
  # todas menos a última de cada conversa.
  def excerpts
    @excerpts ||= last_per_conversation(Message.message_types[:incoming], :content)
  end

  def last_outgoing
    @last_outgoing ||= last_per_conversation(Message.message_types[:outgoing], :id)
  end

  def last_per_conversation(message_type, column)
    return {} if ids.empty?

    Message.where(conversation_id: ids, message_type: message_type, private: false)
           .select(Arel.sql("DISTINCT ON (messages.conversation_id) messages.conversation_id, messages.#{column}"))
           .order(Arel.sql('messages.conversation_id, messages.created_at DESC'))
           .to_h { |row| [row.conversation_id, row[column]] }
  end

  # Só as respostas de verdade: `live` descarta a invocação de playground, que
  # não foi entregue a ninguém.
  def agent_replies
    @agent_replies ||= begin
      message_ids = last_outgoing.values.compact
      if message_ids.empty?
        {}
      else
        Ai::Invocation.live.where(account_id: @account.id, message_id: message_ids)
                      .pluck(:message_id, :ai_assistant_id).to_h
      end
    end
  end

  # Dinheiro parado, quando o radar de leads já estimou a oportunidade daquela
  # conversa. Reusado e não recalculado: o radar já cruza interesse, produto e
  # ticket, e uma segunda estimativa aqui discordaria da que o operador vê na
  # outra aba sobre a mesma cliente.
  def lead_values
    @lead_values ||= Ai::LeadOpportunity.where(account_id: @account.id, conversation_id: ids)
                                        .pluck(:conversation_id, :potential_brl, :interest)
                                        .to_h { |id, brl, interest| [id, { cents: (brl.to_f * 100).round, interest: interest }] }
  end
end
