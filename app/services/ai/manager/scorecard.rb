# As três notas do agente, sempre três, nunca uma.
#
# Não existe nota única aqui de propósito. Um número só esconde qual metade se
# mexeu: um agente que ficou mais barato porque parou de responder sobe na média
# e despenca no negócio, e a média não deixa isso aparecer. Um que passou a
# fechar mais porque virou insistente sobe na conversão e some com a
# confiabilidade. As três lado a lado é a única forma de o operador ver a troca
# que ele acabou de fazer.
#
# Cada uma na sua unidade, porque forçá-las na mesma escala seria inventar uma
# conversão de reais em porcentagem:
#   confiabilidade — % das mensagens entregues que saíram limpas.
#   conversão      — % das conversas que viraram agendamento ou venda.
#   custo          — centavos de real por conversa.
#
# E `nil` em vez de zero quando não há base. "0% de conversão" lê como um agente
# que fracassou; a verdade é que ninguém falou com ele.
class Ai::Manager::Scorecard
  NOTES = %i[reliability conversion cost].freeze

  # Uma mensagem entregue conta como quebrada se QUALQUER chamada do turno saiu
  # torta. Um turno que usa a agenda cobra várias chamadas e todas carregam o
  # mesmo message_id, então a leitura correta é por mensagem: foi assim que o
  # cliente recebeu.
  #
  # `handoff` entra na conta porque uma resposta que precisou passar para um
  # humano é uma resposta que o agente não terminou. E o texto vazio é medido
  # com BOOL_OR sobre o turno inteiro, nunca por linha: só a última chamada de
  # um loop de ferramentas recebe o texto final, e cobrar linha a linha marcaria
  # como falha todo turno que usou a agenda.
  TURN_HEALTH = [
    'message_id',
    "BOOL_OR(auto_flag IS NOT NULL OR status <> 'success' OR delivery_status = 'failed' OR handoff) AS broken",
    "BOOL_OR(ai_response IS NOT NULL AND ai_response <> '') AS answered"
  ].freeze

  HEALTH_TOTALS = 'COUNT(*) AS delivered, COUNT(*) FILTER (WHERE broken OR NOT answered) AS failed'.freeze

  def initialize(scope:)
    @scope = scope
  end

  def perform
    now = notes_for(@scope)
    before = notes_for(previous)
    NOTES.index_with do |note|
      { value: now[note], previous: before[note], change: change(now[note], before[note]) }
    end
  end

  private

  def previous
    @previous ||= @scope.previous
  end

  def notes_for(scope)
    {
      reliability: reliability(scope),
      conversion: conversion(scope),
      cost: cost(scope)
    }
  end

  def reliability(scope)
    total, broken = turn_health(scope)
    return nil if total.zero?

    ((total - broken).to_f / total * 100).round(1)
  end

  # Agregado em SQL, em duas camadas, e não carregado para o Ruby: a tabela de
  # invocações é a que cresce com o tráfego da plataforma inteira, e um mês de
  # uma conta movimentada são dezenas de milhares de linhas para responder uma
  # divisão.
  def turn_health(scope)
    turns = scope.replies.select(Arel.sql(TURN_HEALTH.join(', '))).group(:message_id)
    row = Ai::Invocation.from(turns, :turns).pick(Arel.sql(HEALTH_TOTALS)) || [0, 0]
    [row.first.to_i, row.last.to_i]
  end

  def conversion(scope)
    conversations = scope.conversations_count
    return nil if conversations.zero?

    ((converted(scope).to_f / conversations) * 100).round(1)
  end

  # União de conjuntos, não soma. Uma conversa que agendou E gerou receita é uma
  # conversa convertida, e somar as duas pontas produziria conversão acima de
  # 100% sem que nada de anormal tivesse acontecido.
  #
  # As duas listas são curtas por natureza (agendamentos e vendas do período),
  # ao contrário da lista de conversas, então trazê-las para o Ruby é barato.
  def converted(scope)
    booked = scope.appointments.booked.where.not(conversation_id: nil).distinct.pluck(:conversation_id)
    sold = scope.revenue_events.where.not(conversation_id: nil).distinct.pluck(:conversation_id)
    (booked | sold).length
  end

  def cost(scope)
    conversations = scope.conversations_count
    return nil if conversations.zero?

    (scope.cost_cents_brl.to_f / conversations).round(1)
  end

  # Variação percentual, ou nil quando não existe base. Sair de zero não é
  # "aumento de 100%", é a primeira vez, e a tela precisa poder dizer isso em vez
  # de inventar um número. Mesma regra do painel de Relatórios, de propósito: as
  # duas telas mostram setinhas lado a lado e não podem discordar sobre o que uma
  # seta significa.
  def change(now, before)
    return nil if now.nil? || before.nil? || before.to_f.zero?

    (((now.to_f - before.to_f) / before.to_f) * 100).round(1)
  end
end
