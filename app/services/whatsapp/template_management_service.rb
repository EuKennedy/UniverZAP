# Cria, acompanha e remove templates de mensagem direto do painel, em vez de
# mandar o operador para o Gerenciador da Meta.
#
# ## Por que existe
#
# Sem template não sai campanha, e submeter template era a única etapa do fluxo
# que acontecia inteiramente fora do produto. O operador criava lá, esperava sem
# saber quanto, e voltava aqui torcendo para o sync de 3 horas ter pegado. Já
# existia `Whatsapp::CsatTemplateService` fazendo exatamente estas três chamadas
# — mas com forma fixa de pesquisa de satisfação, então não servia para campanha.
#
# ## O que este serviço NÃO faz
#
# Não acelera a aprovação. Quem aprova é a Meta, e leva de minutos a dias. O que
# ele muda é o operador ver o estado sem sair do lugar, e saber que o pedido foi
# aceito em vez de descobrir depois que nunca chegou.
class Whatsapp::TemplateManagementService
  # A mesma da CsatTemplateService, para as duas falarem com a mesma versão da
  # API. Divergir aqui é a forma mais silenciosa de uma parar de funcionar.
  API_VERSION = 'v14.0'.freeze

  # UTILITY aprova mais rápido e custa menos por conversa; MARKETING é o que
  # promoção exige e é revisado com mais rigor. AUTHENTICATION fica de fora: é
  # código de verificação, não é o que campanha manda, e liberar por engano
  # queima categoria mais barata em uso indevido.
  CATEGORIES = %w[UTILITY MARKETING].freeze

  # A Meta aceita nome só com minúscula, número e underscore. O operador escreve
  # "Promoção de Natal" e o pedido volta com erro que não explica nada.
  NAME_FORMAT = /\A[a-z0-9_]+\z/

  # O produto é pt-BR. Idioma ausente é descuido de quem chamou, não intenção.
  DEFAULT_LANGUAGE = 'pt_BR'.freeze

  Result = Struct.new(:success?, :template, :error, keyword_init: true)

  def initialize(channel)
    @channel = channel
  end

  # Lista o que existe na Meta, com o estado de cada um. É a fonte da verdade:
  # o que está guardado no canal é uma cópia do último sync.
  def list
    response = HTTParty.get("#{business_account_path}/message_templates", headers: api_headers)
    return failure(response) unless response.success?

    Result.new(success?: true, template: Array(response['data']).map { |row| summarise(row) })
  rescue StandardError => e
    crashed(e)
  end

  # Argumentos opcionais de propósito: o controller repassa o que o cliente
  # mandou, e um pedido sem `language` levantaria ArgumentError — 500 no lugar
  # de uma recusa que diz o que faltou.
  def create(name: nil, category: nil, language: nil, body: nil)
    invalid = validation_error(name, category, body)
    return Result.new(success?: false, error: invalid) if invalid

    response = HTTParty.post(
      "#{business_account_path}/message_templates",
      headers: api_headers,
      body: { name: name, language: language.presence || DEFAULT_LANGUAGE, category: category,
              components: [{ type: 'BODY', text: body }] }.to_json
    )
    return failure(response) unless response.success?

    # A resposta da criação traz id e status, mas não o nome — e o operador
    # precisa do nome para achar de novo.
    Result.new(success?: true, template: summarise(response.parsed_response.merge('name' => name)))
  rescue StandardError => e
    crashed(e)
  end

  def destroy(name)
    response = HTTParty.delete("#{business_account_path}/message_templates?name=#{CGI.escape(name)}",
                               headers: api_headers)
    return failure(response) unless response.success?

    Result.new(success?: true, template: { name: name })
  rescue StandardError => e
    crashed(e)
  end

  private

  def validation_error(name, category, body)
    return 'name_format' unless name.to_s.match?(NAME_FORMAT)
    return 'category_unknown' unless CATEGORIES.include?(category)
    return 'body_blank' if body.to_s.strip.empty?

    nil
  end

  def summarise(row)
    {
      id: row['id'], name: row['name'], status: row['status'],
      category: row['category'], language: row['language'],
      # Só vem preenchido quando a Meta recusa, e é a única pista do motivo.
      rejected_reason: row['rejected_reason']
    }
  end

  # O erro da Meta é repassado ao operador porque, aqui, ele é acionável: diz
  # que o nome já existe, que a categoria não bate com o texto, que faltou
  # exemplo. É o oposto da regra do agente, onde a mensagem do salão nunca chega
  # ao cliente — aqui quem lê é quem pode corrigir.
  def failure(response)
    detail = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'message') : nil
    Result.new(success?: false, error: detail.presence || "http_#{response.code}")
  end

  def crashed(error)
    Rails.logger.error("[WHATSAPP] template management failed: #{error.class}: #{error.message}")
    Result.new(success?: false, error: 'unreachable')
  end

  # Respeita a mesma variável de ambiente que a CsatTemplateService: um ambiente
  # que aponta a base para outro lugar precisa mover as duas juntas.
  def business_account_path
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{API_VERSION}/#{@channel.provider_config['business_account_id']}"
  end

  def api_headers
    { 'Authorization' => "Bearer #{@channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end
end
