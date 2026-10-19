# Transforma o `nfm_reply` da Meta no texto que o atendente lê e nos dados que
# a automação usa.
#
# `response_json` chega como STRING com os campos do `complete` mais o
# `flow_token`. O token leva à mensagem original e, por ela, ao Flow — e é do
# Flow JSON que saem os rótulos e os títulos das opções, para o atendente ver
# "Serviço: Corte" e não "servico: corte".
class Whatsapp::Flows::ResponseParser
  Parsed = Struct.new(:content, :flow_response, keyword_init: true)

  def initialize(nfm_reply)
    @nfm_reply = nfm_reply.to_h.with_indifferent_access
  end

  def parse
    answers = JSON.parse(@nfm_reply[:response_json].to_s)
    answers = {} unless answers.is_a?(Hash)
    token = answers.delete('flow_token')
    original = Whatsapp::Flows::FlowToken.message_for(token)
    flow = flow_for(original)

    fields = fields_for(answers, flow)
    Parsed.new(
      content: content_for(fields, flow),
      flow_response: {
        flow_id: flow&.id,
        original_message_id: original&.id,
        fields: fields
      }
    )
  rescue JSON::ParserError
    Parsed.new(content: @nfm_reply[:body].to_s, flow_response: { fields: [] })
  end

  private

  def flow_for(original)
    flow_id = original&.content_attributes&.dig('whatsapp_flow', 'id')
    WhatsappFlow.find_by(id: flow_id) if flow_id
  end

  def fields_for(answers, flow)
    labels = flow&.field_labels || {}
    options = flow&.field_options || {}
    answers.map do |name, raw|
      { name: name, label: labels[name] || name, value: humanize(raw, options[name] || {}), raw: raw }
    end
  end

  def humanize(raw, option_titles)
    case raw
    when Array then raw.map { |item| option_titles[item.to_s] || item.to_s }.join(', ')
    when true then 'Sim'
    when false then 'Não'
    else option_titles[raw.to_s] || raw.to_s
    end
  end

  def content_for(fields, flow)
    lines = fields.reject { |field| field[:value].blank? }.map { |field| "#{field[:label]}: #{field[:value]}" }
    [flow&.name, *lines].compact_blank.join("\n")
  end
end
