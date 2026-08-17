# O contrato de uma verificação do Gerente.
#
# Acrescentar verificação nova é acrescentar UMA classe aqui embaixo e o nome
# dela em Ai::Manager::Checks.all. Nada no motor muda: nem a controller, nem o
# liga/desliga, nem a tela, nem a deduplicação. Isso é requisito e não elegância
# — o catálogo nasce com quatro porque foram quatro falhas vistas no log de
# produção, e a quinta vai aparecer na semana que vem.
#
# Quatro coisas que toda verificação promete:
#
#   key                — identidade estável. Vai para o banco, para a URL do
#                        liga/desliga e para a deduplicação, então renomear uma
#                        é migração, não refatoração.
#   title              — o que o operador lê no cartão.
#   what_it_measures   — a frase que a tela mostra ao lado do interruptor. Sem
#                        ela o operador desliga uma verificação sem saber o que
#                        parou de ser olhado.
#   run(scope)         — uma lista de achados. Vazia é a resposta certa e comum:
#                        falso positivo é o que faz o operador parar de ler a
#                        fila, e uma fila que ninguém lê não vale nada.
#
# No máximo UM achado por agente por rodada. Não é limitação técnica, é decisão
# de produto: cinco cartões dizendo a mesma coisa sobre o mesmo agente é ruído.
# A verificação agrega e mostra o pior caso como evidência. O índice único no
# banco é a rede de baixo.
class Ai::Manager::Checks::Base
  # Trecho de conversa que cabe num cartão. Acima disso o operador rola em vez
  # de decidir.
  EXCERPT_MAX_CHARS = 240

  class << self
    def key
      raise NotImplementedError, "#{name} precisa declarar uma key"
    end

    def title
      raise NotImplementedError, "#{name} precisa declarar um title"
    end

    def what_it_measures
      raise NotImplementedError, "#{name} precisa declarar what_it_measures"
    end

    def severity
      'normal'
    end

    # Qual das duas alavancas este achado puxa: 'training' (memória) ou
    # 'prompt_version' (candidata na disputa A/B).
    def target
      raise NotImplementedError, "#{name} precisa declarar um target"
    end

    # Quanto custa rodar esta verificação por conversa analisada. Zero em todas
    # as quatro da v1, que leem o log e não chamam modelo nenhum. O campo existe
    # porque a tela mostra a estimativa ANTES de rodar, e no dia em que uma
    # verificação precisar de um modelo o número aparece sozinho lá.
    def cost_per_conversation_cents
      0
    end

    def descriptor
      { key: key, title: title, what_it_measures: what_it_measures, severity: severity, target: target }
    end

    # Uma instância por chamada, para que uma verificação possa memoizar à
    # vontade sem vazar o agente anterior para o próximo.
    def run(scope)
      new(scope).run
    end
  end

  def initialize(scope)
    @scope = scope
  end

  def run
    raise NotImplementedError, "#{self.class.name} precisa implementar #run"
  end

  private

  attr_reader :scope

  # O único construtor de achado. Existe para que a chave do hash não seja
  # digitada em quatro arquivos diferentes: um `evidence` escrito `evidences`
  # numa delas passaria calado até a tela abrir vazia em produção.
  def finding(title:, rationale:, evidence:, proposed:)
    {
      check_key: self.class.key,
      severity: self.class.severity,
      target: self.class.target,
      title: title,
      rationale: rationale,
      evidence: evidence,
      proposed: proposed
    }
  end

  # A evidência tem sempre as mesmas quatro peças: onde aconteceu, o que foi
  # dito, qual métrica e quanto deu. Um número sem a frase não convence ninguém
  # a mexer no agente, e a frase sem o número é anedota.
  def evidence(conversation_id:, excerpt:, metric:, value:)
    {
      'conversation_id' => conversation_id,
      'excerpt' => clip(excerpt),
      'metric' => metric,
      'value' => value
    }
  end

  def clip(text)
    text.to_s.squish.truncate(EXCERPT_MAX_CHARS)
  end

  # A frase onde o problema está, e não a resposta inteira. Uma resposta de
  # WhatsApp tem cinco frases e quatro delas estão certas.
  def sentence_containing(text, pattern)
    sentences(text).find { |sentence| sentence.match?(pattern) } || text
  end

  # A única definição de frase deste módulo. Mora aqui porque a verificação de
  # horário lê frase a frase para decidir, e não só para citar: as duas
  # discordarem sobre onde uma frase termina faria o cartão mostrar um trecho
  # diferente do que foi julgado.
  def sentences(text)
    text.to_s.split(/(?<=[.!?\n])\s+/)
  end

  def rate(part, whole)
    return 0.0 if whole.to_i.zero?

    (part.to_f / whole * 100).round(1)
  end
end
