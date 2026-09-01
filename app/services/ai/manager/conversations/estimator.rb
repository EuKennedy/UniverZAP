# Quanto a próxima leitura vai custar, antes de gastar qualquer coisa.
#
# Roda só a triagem, que é SQL, e nunca chama modelo. É por isso que a tela pode
# mostrar "43 conversas, mais ou menos R$ 0,52" antes do clique: a conta que
# encarece é a leitura, e a triagem já sabe exatamente quantas conversas vão
# chegar nela.
#
# Um botão de gastar que não diz quanto vai gastar é um botão que o operador
# clica uma vez e nunca mais.
class Ai::Manager::Conversations::Estimator
  Reader = Ai::Manager::Conversations::Reader

  # Medidos contra o formato real do pedido: o prefixo do sistema é constante e
  # o corpo é o transcrito cortado em doze mensagens de até 320 caracteres. São
  # estimativas por cima, porque prometer barato e cobrar caro é pior que o
  # contrário.
  EXPECTED_INPUT_TOKENS = 1_400
  EXPECTED_OUTPUT_TOKENS = 150

  def initialize(account:, hours:, now: Time.current)
    @account = account
    @hours = hours
    @now = now
  end

  def perform
    {
      window_hours: @hours,
      scanned: triage.scanned,
      candidates: triage.candidates.length,
      will_read: will_read,
      cost_cents_brl: cost_cents_brl,
      triage_findings: triage.findings.length
    }
  end

  private

  def triage
    @triage ||= Ai::Manager::Conversations::Triage.new(
      account: @account, since: @now - @hours.hours, now: @now
    )
  end

  def will_read
    [triage.candidates.length, Reader::MAX_READ].min
  end

  # O total de tokens de uma vez, e não o preço de uma conversa multiplicado.
  # O cálculo arredonda para centavo inteiro no fim, então multiplicar depois
  # de arredondar transforma 1,72 centavo em 2 e infla a estimativa em 16%.
  # Prometer barato e cobrar caro seria pior, mas prometer caro faz o operador
  # não clicar num botão que custava a metade.
  def cost_cents_brl
    return 0 if will_read.zero?

    Ai::PricingCalculator.cost_cents_brl(
      model: Reader::MODEL,
      input_tokens: EXPECTED_INPUT_TOKENS * will_read,
      output_tokens: EXPECTED_OUTPUT_TOKENS * will_read
    )
  end
end
