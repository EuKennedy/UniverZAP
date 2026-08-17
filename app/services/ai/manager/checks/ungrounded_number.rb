# O agente tentou inventar um valor, e a guarda teve que reescrever a resposta.
#
# Leia o título de novo, porque a diferença importa e é fácil de errar aqui: o
# que esta verificação encontra NÃO é um preço inventado que chegou ao cliente.
# Quando a reescrita também sai com valor sem fonte, a resposta inteira é jogada
# fora e a conversa vai para um humano (Ai::AutopilotReplyJob trata
# UngroundedClaim com hand_off), então aquela linha do log nunca recebe
# `message_id` e nunca entra neste escopo. O que sobra aqui é sempre uma
# tentativa que a guarda consertou a tempo.
#
# Isso não a torna barulho. A tentativa é o sinal que interessa ao dono da
# operação, e é exatamente o que Ai::KnowledgeGrounding diz ao levantar a
# bandeira: alguém perguntou um preço que não está escrito em lugar nenhum, e o
# modelo produziu um plausível. Enquanto a tabela não estiver na base, a única
# coisa entre o cliente e um número inventado é uma regeneração que pode falhar
# na próxima. É por isso que uma ocorrência já basta.
#
# Duas condições, e as duas precisam valer: a bandeira `preco_inventado`, e o
# texto entregue ainda citar valor. A segunda é filtro de evidência e não de
# gravidade: sem ela o cartão mostraria como prova uma frase sem número nenhum.
#
# O resultado de ferramenta não é persistido, então a verificação não consegue
# reconferir sozinha contra ele. Ela lê o julgamento que já foi feito no
# momento certo, com as fontes em mãos, em vez de fabricar um segundo julgamento
# pior alguns dias depois.
class Ai::Manager::Checks::UngroundedNumber < Ai::Manager::Checks::Base
  FLAG = 'preco_inventado'.freeze

  # Teto de linhas lidas: o filtro final é em Ruby (a regex de valor roda sobre
  # o texto), então a rodada precisa de um limite que não dependa do tamanho da
  # conta.
  MAX_ROWS = 500

  def self.key
    'ungrounded_number'
  end

  def self.title
    'Preço inventado que a guarda precisou reescrever'
  end

  def self.what_it_measures
    'Respostas em que o agente citou um preço que não existe em nenhuma fonte e teve que ser reescrito.'
  end

  # Um só já basta. Um preço inventado no WhatsApp é promessa comercial que
  # alguém vai ter que honrar ou desmentir na frente do cliente, e a média de
  # respostas certas não paga essa conta.
  def self.severity
    'critical'
  end

  def self.target
    'training'
  end

  def run
    offenders = ungrounded_replies
    return [] if offenders.empty?

    [build_finding(offenders)]
  end

  private

  def ungrounded_replies
    @ungrounded_replies ||= scope.replies.where('auto_flags @> ?', [FLAG].to_json)
                                 .where.not(ai_response: [nil, ''])
                                 .order(created_at: :desc).limit(MAX_ROWS)
                                 .pluck(:conversation_id, :ai_response, :message_id)
                                 .select { |row| row[1].match?(Ai::KnowledgeGrounding::MONETARY_CLAIM) }
  end

  def build_finding(offenders)
    conversation_id, text, = offenders.first
    # Contado por mensagem entregue, e não por linha do log: um turno que usou a
    # agenda grava várias chamadas com o mesmo message_id.
    count = offenders.map(&:last).uniq.length
    finding(
      title: 'O agente tentou citar um valor que não existe na base',
      rationale: rationale_for(count),
      evidence: evidence(
        conversation_id: conversation_id,
        # O texto DEPOIS da reescrita, que é o único que existe gravado: o valor
        # que o agente tentou inventar morre no log do guardrail. Serve para
        # achar a conversa, não como prova do número errado, e é isto que a
        # justificativa acima diz com todas as letras.
        excerpt: sentence_containing(text, Ai::KnowledgeGrounding::MONETARY_CLAIM),
        metric: 'respostas_reescritas_pela_guarda', value: count
      ),
      proposed: proposed_document
    )
  end

  def rationale_for(count)
    "Em #{count} resposta(s) do período o agente escreveu um valor que não aparece na base de conhecimento, " \
      'nas instruções dele nem no que o cliente escreveu, e a guarda teve que reescrever a resposta antes ' \
      'de ela sair. Nenhum cliente recebeu esses números, e é justamente por isso que vale olhar agora: ' \
      'quando o preço não está escrito em lugar nenhum, o modelo produz um plausível toda vez, e a única ' \
      'coisa entre o cliente e esse número é uma reescrita que pode não vir limpa na próxima. ' \
      'O trecho abaixo é o texto que saiu DEPOIS da reescrita, e está aqui para você achar a conversa: ' \
      'o valor que o agente tentou inventar não fica gravado em lugar nenhum. ' \
      'A correção definitiva é colocar a tabela de valores na base; este documento é a regra que ' \
      'segura o agente enquanto ela não está lá.'
  end

  def proposed_document
    {
      'title' => 'Regra de valores desta operação',
      'category' => 'policies',
      'content' => POLICY
    }
  end

  POLICY = <<~DOC.strip.freeze
    Só informe preço, desconto, prazo ou condição de pagamento que esteja escrito
    literalmente nesta base de conhecimento.

    Se o cliente perguntar um valor que não está aqui: diga que vai confirmar com
    a equipe, peça o melhor horário para retornar e siga a conversa. Não estime,
    não arredonde, não deduza por semelhança e não reaproveite o preço de outro
    serviço.

    Deixar de informar um valor é aceitável. Informar um valor errado não é: quem
    responde por ele depois é a pessoa no balcão.
  DOC
end
