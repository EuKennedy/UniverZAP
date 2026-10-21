# Monta o texto final de UM destinatário a partir do modelo:
#
#   1. escolhe uma das versões do texto (o operador pode escrever 2–3, ou pedir
#      à IA), para que o número não mande a mesma mensagem idêntica 150 vezes;
#   2. resolve o spintax `{Oi|Olá|Oie}` — chaves com barra;
#   3. troca as variáveis {nome}, {primeiro_nome}, {servico}, {profissional},
#      {ultima_visita} e as antigas {contact.*}.
#
# A escolha usa `seed` (o id do destinatário / da mensagem agendada): a
# pré-visualização mostra exatamente o que aquela cliente vai receber.
class Broadcasts::MessageRenderer
  VARIABLES = %w[nome primeiro_nome servico profissional ultima_visita].freeze
  VARIABLE = /\{(#{VARIABLES.join('|')})\}/
  SPIN = /\{([^{}]*\|[^{}]*)\}/

  def initialize(contact:, conversation: nil, seed: nil)
    @contact = contact
    @conversation = conversation
    @random = Random.new(seed.to_i)
  end

  def render(text, variants: [])
    template = pick_version(text, variants)
    return '' if template.blank?

    filled = Broadcasts::ContactTokenResolver.new(@contact).resolve(spin(template))
    filled.gsub(VARIABLE) { value_for(Regexp.last_match(1)) }.gsub(/[ \t]{2,}/, ' ').strip
  end

  # Variáveis do texto que ficariam vazias para este contato (ex.: cliente sem
  # serviço gravado). A pré-visualização avisa antes de disparar.
  def missing_variables(*texts)
    texts.flatten.compact.join(' ').scan(VARIABLE).flatten.uniq.select { |name| value_for(name).blank? }
  end

  def first_name
    name = clean_name
    return '' if name.blank?

    name.split(/\s+/).first.to_s.capitalize
  end

  private

  def pick_version(text, variants)
    versions = [text, *Array(variants)].map(&:to_s).compact_blank
    versions[@random.rand(versions.size)] if versions.any?
  end

  def spin(text)
    result = text.dup
    result = result.gsub(SPIN) { Regexp.last_match(1).split('|', -1).then { |opts| opts[@random.rand(opts.size)] } } while result.match?(SPIN)
    result
  end

  def value_for(name)
    @values ||= {}
    @values[name] ||= compute(name).to_s
  end

  def compute(name)
    case name
    when 'nome' then clean_name
    when 'primeiro_nome' then first_name
    when 'servico', 'profissional' then attribute(name)
    when 'ultima_visita' then last_visit
    end
  end

  # Nome de WhatsApp vem com número, "~", emoji… Um "Oi +55 31 9…" denuncia a
  # automação na hora; melhor sem nome do que com o número no lugar dele.
  def clean_name
    name = @contact.name.to_s.delete('~').strip
    return '' if name.blank? || name.match?(/\d{4,}|@/)

    name.gsub(/[^\p{L}\p{M}\s'.-]/, '').squish
  end

  def attribute(key)
    (@conversation&.custom_attributes || {})[key].presence || (@contact.custom_attributes || {})[key].presence
  end

  def last_visit
    raw = (@contact.custom_attributes || {})['ultima_visita'].presence || belezaki_last_visit
    return '' if raw.blank?

    Time.zone.parse(raw.to_s)&.strftime('%d/%m') || raw.to_s
  rescue ArgumentError
    raw.to_s
  end

  # Só a conta ligada ao Belezaki tem a última visita; o card tem cache de 1 min.
  def belezaki_last_visit
    return if @contact.account.blank? || Belezaki::TenantResolver.external_id(@contact.account).blank?

    Belezaki::CustomerCardService.new(account: @contact.account, contact: @contact).perform.dig(:stats, 'last_visit_at')
  rescue StandardError => e
    Rails.logger.warn("[Broadcast render] belezaki last visit contact=#{@contact.id}: #{e.message}")
    nil
  end
end
