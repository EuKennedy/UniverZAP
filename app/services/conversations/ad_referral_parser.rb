# Line-by-line reader of the ad block WAHA's Chatwoot App renders from
# `contextInfo.externalAdReply` (template whatsapp.to.chatwoot.message.facebook.ad,
# pt-BR and en-US): header, three labelled lines, a multi-line description,
# a `---` rule and the customer's own text.
class Conversations::AdReferralParser
  HEADER = /📢\s*\**\s*(?:ANÚNCIO DO FACEBOOK|FACEBOOK AD)/i
  CUSTOMER_MESSAGE = /(?:MENSAGEM DO CLIENTE|CUSTOMER'?S? MESSAGE)/i
  FIELDS = {
    'title' => /\A\**(?:Título|Title):\**\s*(.*)\z/i,
    'ad_id' => /\A\**(?:ID do Anúncio|Ad ID):\**\s*(.*)\z/i,
    'url' => /\A\**(?:Link do Anúncio|Ad Link):\**\s*(.*)\z/i
  }.freeze
  BODY = /\A\**(?:Descrição|Description):\**\s*(.*)\z/i

  def self.ad_message?(content)
    content.to_s.match?(HEADER)
  end

  def initialize(content)
    @lines = content.to_s.split("\n").map(&:strip)
    @result = { 'source' => 'facebook' }
    @body = []
    @customer = nil
    @collecting_body = false
  end

  def data
    @lines.each { |line| read(line) }

    @result['url'] = @result['url'].to_s[%r{https?://[^\s)]+}] if @result['url']
    @result['body'] = @body.join("\n").strip
    @result['customer_message'] = Array(@customer).join("\n").strip
    @result
  end

  private

  def read(line)
    return if line.match?(HEADER)
    return @customer << line if @customer
    return @customer = [] if line.match?(CUSTOMER_MESSAGE)

    field, value = labelled(line)
    return store(field, value) if field

    read_body(line)
  end

  def store(field, value)
    @result[field] = value
    @collecting_body = false
  end

  def read_body(line)
    if (match = line.match(BODY))
      @collecting_body = true
      @body << match[1] if match[1].present?
    elsif line == '---'
      @collecting_body = false
    elsif @collecting_body
      @body << line
    end
  end

  def labelled(line)
    FIELDS.each do |field, pattern|
      match = line.match(pattern)
      return [field, match[1].delete('*').strip] if match
    end
    nil
  end
end
