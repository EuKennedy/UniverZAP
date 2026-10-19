# Cria, publica, deprecia e sincroniza Flows na Meta, pela Flows API do WABA.
#
# Mesmo desenho do TemplateManagementService: o Result diz se deu certo e,
# quando não deu, repassa o motivo da Meta — aqui quem lê é quem corrige.
#
# Ciclo de vida na Meta: DRAFT → PUBLISHED → DEPRECATED. Publicado não se
# edita nem se apaga; o JSON novo só entra num Flow novo.
class Whatsapp::Flows::ManagementService
  Result = Struct.new(:success?, :flow, :error, keyword_init: true)

  def initialize(channel)
    @channel = channel
  end

  # Cria o Flow na Meta na primeira vez; depois, só reenvia o JSON.
  def push(flow)
    flow.meta_flow_id.present? ? update_json(flow) : create(flow)
  end

  def create(flow)
    response = HTTParty.post(
      "#{business_account_path}/flows",
      headers: api_headers,
      body: { name: flow.name, categories: [flow.category], flow_json: flow.flow_json.to_json }.to_json
    )
    return failure(response) unless response.success?

    flow.update!(meta_flow_id: response['id'], validation_errors: Array(response['validation_errors']))
    Result.new(success?: true, flow: flow)
  rescue StandardError => e
    crashed(e)
  end

  # A Meta recebe o JSON como ARQUIVO (multipart), não como campo do corpo.
  def update_json(flow)
    Tempfile.create(['flow', '.json']) do |file|
      file.write(flow.flow_json.to_json)
      file.rewind
      response = HTTParty.post(
        "#{flow_path(flow)}/assets",
        headers: { 'Authorization' => "Bearer #{api_key}" },
        multipart: true,
        body: { name: 'flow.json', asset_type: 'FLOW_JSON', file: file }
      )
      return failure(response) unless response.success?

      flow.update!(validation_errors: Array(response['validation_errors']))
    end
    Result.new(success?: true, flow: flow)
  rescue StandardError => e
    crashed(e)
  end

  def publish(flow)
    return Result.new(success?: false, error: 'not_on_meta') if flow.meta_flow_id.blank?

    response = HTTParty.post("#{flow_path(flow)}/publish", headers: api_headers)
    return failure(response) unless response.success?

    flow.update!(status: 'published', published_at: Time.current)
    Result.new(success?: true, flow: flow)
  rescue StandardError => e
    crashed(e)
  end

  def deprecate(flow)
    response = HTTParty.post("#{flow_path(flow)}/deprecate", headers: api_headers)
    return failure(response) unless response.success?

    flow.update!(status: 'deprecated')
    Result.new(success?: true, flow: flow)
  rescue StandardError => e
    crashed(e)
  end

  # Estado e link de prévia (30 dias, sem login) direto da Meta. A prévia
  # interativa é a única forma de testar sem mandar para um telefone.
  def sync(flow)
    response = HTTParty.get(
      "#{flow_path(flow)}?fields=status,validation_errors,preview.invalidate(false)",
      headers: api_headers
    )
    return failure(response) unless response.success?

    flow.update!(
      status: response['status'].to_s.downcase.presence || flow.status,
      validation_errors: Array(response['validation_errors']),
      preview_url: response.dig('preview', 'preview_url')
    )
    Result.new(success?: true, flow: flow)
  rescue StandardError => e
    crashed(e)
  end

  # Só rascunho se apaga na Meta. O resto fica lá (depreciado) e some só daqui.
  def destroy(flow)
    if flow.draft? && flow.meta_flow_id.present?
      response = HTTParty.delete(flow_path(flow), headers: api_headers)
      return failure(response) unless response.success?
    end

    flow.destroy!
    Result.new(success?: true, flow: flow)
  rescue StandardError => e
    crashed(e)
  end

  private

  def failure(response)
    detail = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'message') : nil
    Result.new(success?: false, error: detail.presence || "http_#{response.code}")
  end

  def crashed(error)
    Rails.logger.error("[WHATSAPP FLOWS] #{error.class}: #{error.message}")
    Result.new(success?: false, error: 'unreachable')
  end

  def api_key
    @channel.provider_config['api_key']
  end

  def api_headers
    { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' }
  end

  def api_base_path
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')}"
  end

  def business_account_path
    "#{api_base_path}/#{@channel.provider_config['business_account_id']}"
  end

  def flow_path(flow)
    "#{api_base_path}/#{flow.meta_flow_id}"
  end
end
