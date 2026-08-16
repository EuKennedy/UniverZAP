# A janela de tempo que o painel está olhando, e a janela imediatamente
# anterior de mesmo tamanho.
#
# Existe para tirar aritmética de data de dentro de cinco classes de métrica.
# Antes cada uma montava a própria janela com `@days.days.ago..`, o que travava
# o painel em períodos que terminam agora: não dava para pedir "o mês passado"
# nem um intervalo escolhido no calendário, porque a janela era sempre
# ancorada no instante da requisição.
#
# `previous` é o que permite responder a pergunta que todo painel de negócio
# precisa responder e o nosso não respondia: 1.240 respostas é muito ou pouco?
# Número sem tendência é só número.
class Ai::Reports::Period
  DEFAULT_DAYS = 30
  # Um ano e um dia. O teto existe porque cada requisição varre o log de
  # chamadas duas vezes, a janela pedida e a anterior, e alguém digitando 2015
  # no calendário não deveria conseguir varrer a instalação inteira.
  MAX_DAYS = 366

  attr_reader :starts_at, :ends_at, :zone

  # Aceita as três formas que a tela pode pedir, nesta ordem de precedência:
  # um intervalo explícito do calendário, um número de dias, ou o padrão.
  def self.from_params(since: nil, until_at: nil, days: nil)
    explicit = build_from_timestamps(since, until_at)
    return explicit if explicit

    length = days.to_i
    length = DEFAULT_DAYS unless length.positive?
    from_days(length)
  end

  # "Últimos 30 dias" é hoje mais os 29 anteriores, e não 30 dias contados para
  # trás a partir deste instante: a segunda leitura atravessa 31 datas locais e
  # a série sai com uma coluna a mais, meio vazia, na ponta esquerda.
  def self.from_days(days)
    length = days.to_i.clamp(1, MAX_DAYS)
    new(starts_at: (length - 1).days.ago, ends_at: Time.current)
  end

  # Nil quando o par não é utilizável, para o chamador cair no padrão em vez de
  # explodir: uma data digitada errada não pode derrubar o relatório.
  def self.build_from_timestamps(since, until_at)
    from = parse(since)
    to = parse(until_at)
    return nil if from.nil? || to.nil? || from >= to

    # Invertido pelo teto e não recusado: quem pediu cinco anos quer o máximo
    # que a gente dá, e não uma mensagem de erro.
    from = to - (MAX_DAYS - 1).days if (to - from) > (MAX_DAYS - 1).days
    new(starts_at: from, ends_at: to)
  end

  def self.parse(value)
    return nil if value.blank?

    Time.zone.at(Integer(value))
  rescue ArgumentError, TypeError, RangeError
    nil
  end

  def initialize(starts_at:, ends_at:, zone: Time.zone)
    @starts_at = starts_at
    @ends_at = ends_at
    @zone = zone
  end

  # O dia começa à meia-noite do negócio, não à meia-noite do servidor.
  #
  # Sem isto uma conta em São Paulo com o app rodando em UTC começa a janela às
  # 21h da véspera, e a primeira coluna do gráfico é uma noite solta que ninguém
  # pediu. Só o começo é ajustado: o fim é agora, e agora é agora em qualquer
  # fuso.
  def align_to(zone)
    self.class.new(starts_at: starts_at.in_time_zone(zone).beginning_of_day, ends_at: ends_at, zone: zone)
  end

  def range
    starts_at..ends_at
  end

  def length
    ends_at - starts_at
  end

  # As datas locais que a janela cobre, em ordem, e a única definição de "dia"
  # que este módulo tem. A série diária preenche por cima desta lista e o
  # cabeçalho conta o tamanho dela, então o gráfico e o rótulo acima dele não
  # conseguem discordar sobre quantos dias estão sendo mostrados.
  def local_days
    first = starts_at.in_time_zone(zone).to_date
    last = ends_at.in_time_zone(zone).to_date
    (first..last).map(&:to_s)
  end

  def days
    local_days.length
  end

  # O mesmo tamanho, imediatamente antes. Comparar março com fevereiro seria
  # comparar 31 dias com 28, então o que vale é a duração e não o mês.
  def previous
    self.class.new(starts_at: starts_at - length, ends_at: starts_at, zone: zone)
  end
end
