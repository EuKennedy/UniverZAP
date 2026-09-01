# O que o log do agente já sabe sobre cada conversa, sem custo nenhum.
#
# Duas coisas que a leitura por modelo enxergaria pior do que uma consulta:
#
# 1. Repetição. "O agente mandou a mesma resposta três vezes" é uma comparação
#    de strings, e é o sinal mais confiável de que ele travou: quando não sabe
#    avançar, ele reformula a mesma coisa até o cliente desistir. Um modelo
#    lendo o mesmo diálogo chamaria isso de "atendimento consistente".
#
# 2. Bandeira de guardrail. `auto_flag` já foi decidido no momento da resposta,
#    por quem tinha o contexto que o log não guarda (se a ferramenta rodou, se
#    o preço veio da base). Reavaliar aqui produziria uma opinião pior sobre o
#    mesmo texto, e cobraria por ela.
#
# O Gerente já lê essas mesmas bandeiras, e de propósito por outro ângulo: lá
# elas viram taxa da conta ("8% das respostas inventaram preço") para corrigir a
# instrução; aqui elas viram endereço ("nesta conversa, com esta cliente") para
# alguém ir consertar hoje. Mesmo dado, dois usos que não se substituem.
class Ai::Manager::Conversations::AgentSignals
  # Teto de linhas lidas por rodada, igual às verificações do Gerente: a leitura
  # de uma conta grande precisa custar o mesmo que a de uma pequena.
  MAX_ROWS = 800

  # Duas iguais já é padrão. A terceira só confirma o que a segunda mostrou, e
  # esperar por ela é deixar o cliente mais um turno preso no mesmo laço.
  MIN_REPEATS = 2

  def initialize(account:, since:)
    @account = account
    @since = since
  end

  # conversation_id => { count:, excerpt: } para quem repetiu.
  def repeated
    @repeated ||= repeated_rows.each_with_object({}) do |record, acc|
      id = record.conversation_id
      count = record.repeats.to_i
      next if id.blank?
      # A pior repetição da conversa, e não a primeira encontrada: se o agente
      # travou em dois pontos diferentes, o cartão mostra o laço mais longo.
      next if acc[id] && acc[id][:count] >= count

      acc[id] = { count: count, excerpt: record.ai_response.to_s }
    end
  end

  # conversation_id => { flag:, excerpt:, at: } para quem levantou bandeira.
  # A mais recente de cada conversa, porque é a que ainda está de pé na tela do
  # cliente.
  def flagged
    @flagged ||= flagged_rows.each_with_object({}) do |(conversation_id, flag, response, at), acc|
      next if conversation_id.blank? || acc.key?(conversation_id)

      acc[conversation_id] = { flag: flag.to_s, excerpt: response.to_s, at: at }
    end
  end

  private

  def base
    Ai::Invocation.live.replies.where(account_id: @account.id, created_at: @since..)
  end

  # Apelidada e lida como atributo pelo mesmo motivo de
  # Ai::Manager::Conversations::Activity: `pluck` com três colunas dentro de um
  # Arel.sql só decide o formato do retorno pelo número de ARGUMENTOS, e a
  # contagem voltaria colada na mesma linha do texto.
  def repeated_rows
    base.where.not(ai_response: [nil, ''])
        .group(:conversation_id, :ai_response)
        .having(Arel.sql("COUNT(*) >= #{MIN_REPEATS}"))
        .limit(MAX_ROWS)
        .select(Arel.sql('ai_invocations.conversation_id, ai_invocations.ai_response, COUNT(*) AS repeats'))
  end

  def flagged_rows
    base.where.not(auto_flag: nil)
        .order(created_at: :desc).limit(MAX_ROWS)
        .pluck(:conversation_id, :auto_flag, :ai_response, :created_at)
  end
end
