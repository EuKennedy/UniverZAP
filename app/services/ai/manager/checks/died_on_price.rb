# A conversa chegou no preço e morreu ali.
#
# É o único dos quatro que não parte de uma falha de forma: o agente respondeu,
# não inventou nada, não prometeu nada, e mesmo assim a pessoa sumiu. O sinal
# vem do radar comercial, que já grava por que cada conversa parou
# (`block_reason`), cruzado com o que o mesmo agente conseguiu fechar no período
# (Ai::Reports::CommercialMetrics). Sem esse segundo lado o número não diz nada:
# 20 conversas mortas no preço num agente que fechou 60 agendamentos é uma
# operação saudável, e num que fechou 2 é a operação inteira.
#
# `followed` fica de fora do numerador de propósito: ali um humano já pegou o
# lead, e cobrar de novo uma conversa que alguém está perseguindo é o tipo de
# ruído que faz a fila deixar de ser lida.
class Ai::Manager::Checks::DiedOnPrice < Ai::Manager::Checks::Base
  DEAD_STATUSES = %w[open lost].freeze
  BLOCK_REASON = 'pediu_preco'.freeze

  MIN_DEAD = 3
  MIN_RATE = 10.0

  def self.key
    'died_on_price'
  end

  def self.title
    'Conversa que chegou no preço e terminou sem agendar'
  end

  def self.what_it_measures
    'Quantas conversas pararam na pergunta de valor, comparadas ao que o agente fechou no mesmo período.'
  end

  def self.severity
    'high'
  end

  def self.target
    'training'
  end

  def run
    conversations = scope.conversations_count
    return [] if conversations.zero?

    dead = price_blocked.count
    percentage = rate(dead, conversations)
    return [] if dead < MIN_DEAD || percentage < MIN_RATE

    [build_finding(dead, conversations, percentage)]
  end

  private

  def price_blocked
    @price_blocked ||= scope.leads.where(block_reason: BLOCK_REASON, status: DEAD_STATUSES)
  end

  def build_finding(dead, conversations, percentage)
    lead = price_blocked.hottest_first.first
    finding(
      title: 'As conversas estão morrendo na pergunta de preço',
      rationale: rationale_for(dead, conversations),
      evidence: evidence(
        conversation_id: lead&.conversation_id,
        excerpt: last_reply_in(lead&.conversation_id),
        metric: 'porcentagem_das_conversas', value: percentage
      ),
      proposed: proposed_document
    )
  end

  def last_reply_in(conversation_id)
    return nil if conversation_id.blank?

    scope.replies.where(conversation_id: conversation_id).where.not(ai_response: [nil, ''])
         .order(created_at: :desc).pick(:ai_response)
  end

  # Agendamentos do MESMO agente, lidos do painel comercial. É o denominador que
  # transforma uma contagem em julgamento.
  def bookings
    scope.commercial_row[:bookings].to_i
  end

  def rationale_for(dead, conversations)
    closed = bookings
    "#{dead} de #{conversations} conversas do período pararam logo depois da pergunta de preço, " \
      "enquanto o agente fechou #{closed} agendamento(s) no mesmo intervalo. " \
      'O padrão quase sempre é o mesmo: o número sai sozinho, sem o que está incluso, sem prazo e sem ' \
      'uma próxima ação concreta, e a pessoa vai comparar em outro lugar. ' \
      'Se a sua tabela de valores ainda não está na base do agente, é ela que resolve isto de verdade, ' \
      'e este documento é o que ensina o agente a usá-la.'
  end

  def proposed_document
    {
      'title' => 'Como responder pergunta de preço',
      'category' => 'sales',
      'content' => POLICY
    }
  end

  # Só política, nunca valor. O Gerente não pode inventar preço pela mesma razão
  # que o agente não pode: um número nesta base vira promessa comercial que o
  # dono da operação tem que honrar ou desmentir.
  POLICY = <<~DOC.strip.freeze
    Quando o cliente perguntar preço, a resposta tem que sair completa numa
    mensagem só:

    1. O valor exato que está escrito nesta base. Se não estiver escrito aqui,
       diga que vai confirmar com a equipe e peça o melhor horário para retornar.
       Nunca estime e nunca reaproveite o preço de outro serviço.
    2. O que está incluso nesse valor e quanto tempo leva.
    3. As formas de pagamento aceitas.
    4. Uma próxima ação concreta, com dia e hora reais lidos da agenda. Ofereça
       dois horários em vez de perguntar "quer agendar?".

    Se o cliente disser que está caro, não repita o número nem dê desconto por
    conta própria: pergunte o que ele está comparando e responda o que muda de um
    para o outro.
  DOC
end
