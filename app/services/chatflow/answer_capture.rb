# Valida e grava a resposta de uma etapa "Pergunta".
#
# O cliente responde como fala: "meu email é Ana@Gmail.com", "11 98888-7777",
# "20/05". A validação extrai o valor útil do texto, normaliza (e-mail em
# minúsculas, telefone com +55, data em ISO) e devolve nil quando não há nada
# aproveitável — aí o motor manda a mensagem de erro e conta a tentativa.
#
# Onde grava (config['save_to']):
#   { 'scope' => 'contact', 'key' => 'email' }       — campo do contato (name, email, phone_number)
#   { 'scope' => 'contact', 'key' => 'aniversario' } — atributo personalizado do contato
#   { 'scope' => 'conversation', 'key' => 'servico' } — atributo personalizado da conversa
class Chatflow::AnswerCapture
  FIELD_TYPES = %w[name email phone date number text].freeze
  CONTACT_FIELDS = %w[name email phone_number].freeze
  TEXT_LIMIT = 1000

  def initialize(node, conversation)
    @node = node
    @conversation = conversation
  end

  def field_type
    FIELD_TYPES.include?(@node.config['field_type']) ? @node.config['field_type'] : 'text'
  end

  # O valor normalizado, ou nil quando a resposta não serve.
  def parse(text)
    raw = text.to_s.strip
    return nil if raw.blank?

    send(:"parse_#{field_type}", raw)
  end

  # Grava o valor e devolve a chave usada. Um telefone ou e-mail que já pertence
  # a outro contato não derruba o fluxo: o valor fica no contexto da execução e
  # o atendente vê a resposta na conversa de qualquer forma.
  def save(value)
    scope, key = target
    return key if key.blank?

    if scope == 'conversation'
      @conversation.update!(custom_attributes: @conversation.custom_attributes.to_h.merge(key => value))
    elsif CONTACT_FIELDS.include?(key)
      @conversation.contact.update!(key => value)
    else
      contact = @conversation.contact
      contact.update!(custom_attributes: contact.custom_attributes.to_h.merge(key => value))
    end
    key
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.info("[Chatflow question] #{key}: #{e.message}")
    key
  end

  def target
    save_to = @node.config['save_to'].to_h
    scope = save_to['scope'] == 'conversation' ? 'conversation' : 'contact'
    [scope, save_to['key'].to_s.strip.presence]
  end

  private

  # Nome: tira "meu nome é", exige letras e corta no tamanho de um nome.
  def parse_name(raw)
    name = raw.sub(/\A(meu nome [ée]|me chamo|sou (a|o)?|aqui [ée] (a|o)?)\s*/i, '').squish
    return nil unless name.match?(/\p{L}{2,}/) && name.length <= 80

    name
  end

  def parse_email(raw)
    raw[/[^\s@<>()]+@[^\s@<>()]+\.[a-z]{2,}/i]&.downcase&.delete_suffix('.')
  end

  # Telefone brasileiro: DDD + 8/9 dígitos, com ou sem 55 na frente.
  def parse_phone(raw)
    digits = raw.gsub(/\D/, '')
    digits = "55#{digits}" if digits.length.between?(10, 11)
    return nil unless digits.length.between?(12, 13) && digits.start_with?('55')

    "+#{digits}"
  end

  # dd/mm/aaaa, dd/mm/aa, dd-mm-aaaa, dd/mm (ano corrente) ou aaaa-mm-dd.
  def parse_date(raw)
    if (iso = raw.match(/(\d{4})-(\d{1,2})-(\d{1,2})/))
      return build_date(iso[1], iso[2], iso[3])
    end

    br = raw.match(%r{(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?})
    return nil unless br

    year = br[3].presence || Time.zone.today.year.to_s
    year = two_digit_year(year) if year.length == 2
    build_date(year, br[2], br[1])
  end

  # "90" é 1990 (aniversário), "27" é 2027 (agendamento).
  def two_digit_year(year)
    century = year.to_i > (Time.zone.today.year % 100) + 5 ? 1900 : 2000
    (century + year.to_i).to_s
  end

  def build_date(year, month, day)
    Date.new(year.to_i, month.to_i, day.to_i).iso8601
  rescue Date::Error
    nil
  end

  # "1.234,56", "12,5", "R$ 30" → número. Vírgula é decimal, como se escreve aqui.
  def parse_number(raw)
    token = raw[/-?\d[\d.,]*/]
    return nil if token.blank?

    normalized = token.include?(',') ? token.delete('.').tr(',', '.') : token
    number = Float(normalized, exception: false)
    return nil if number.nil?

    number == number.to_i ? number.to_i : number
  end

  def parse_text(raw)
    raw.truncate(TEXT_LIMIT)
  end
end
