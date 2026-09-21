# O que um turno pode gastar: tempo e dinheiro, na mesma régua.
#
# Os dois nasceram separados dentro do Ai::Agent::ToolLoopService e são a mesma
# pergunta feita duas vezes — "dá para fazer mais uma volta?". Juntos aqui, o
# loop volta a tratar só de loop, e quem for acrescentar um terceiro limite
# (iterações, tokens de contexto) tem onde pôr.
#
# ## Por que tempo não bastava
#
# Seis iterações rápidas custam mais que uma lenta, e o que cresce a cada volta
# é o transcript: toda iteração reenvia tudo que as anteriores mandaram MAIS os
# resultados que elas colheram. Um turno podia terminar dentro dos 90 segundos e
# ainda assim gastar vários reais.
class Ai::Agent::TurnBudget
  SECONDS = 90
  # Em centavos de real. Acima disto o turno para de pedir ferramenta e responde
  # com o que já tem.
  MAX_CENTS_BRL = 500

  attr_reader :spent_cents, :spent_tokens

  def initialize(seconds: SECONDS, max_cents: MAX_CENTS_BRL)
    @deadline = monotonic_now + seconds
    @max_cents = max_cents
    @spent_cents = 0.0
    @spent_tokens = [0, 0]
  end

  # Toda chamada passa por aqui, inclusive a forçada e a final: elas acontecem
  # FORA da contagem das iterações e gastam igual.
  def charge(response)
    invocation = response&.dig(:invocation)
    return response if invocation.nil?

    @spent_cents += invocation.cost_brl.to_f * 100
    @spent_tokens = [
      @spent_tokens.first + invocation.input_tokens.to_i,
      @spent_tokens.last + invocation.output_tokens.to_i
    ]
    response
  end

  def exhausted?
    out_of_time? || out_of_money?
  end

  def out_of_time?
    monotonic_now >= @deadline
  end

  def out_of_money?
    @spent_cents >= @max_cents
  end

  # Para o log dizer qual dos dois estourou: "demorou" e "ficou caro" pedem
  # providências diferentes de quem for olhar.
  def reason
    return 'tempo' if out_of_time?
    return 'dinheiro' if out_of_money?

    nil
  end

  private

  # Relógio monotônico: mudança de horário de verão ou ajuste de NTP no meio do
  # turno não pode encurtar nem esticar o orçamento.
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
