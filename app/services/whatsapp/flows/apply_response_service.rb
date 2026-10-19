# Leva a resposta de um Flow para onde o painel trabalha: atributos da
# conversa ou do contato e etiquetas, conforme o mapeamento do Flow.
#
# Roda num job, depois da mensagem já estar na conversa: gravar atributo é
# secundário diante de o atendente VER a resposta, e um mapeamento quebrado
# não pode derrubar o webhook.
class Whatsapp::Flows::ApplyResponseService
  def initialize(message)
    @message = message
    @conversation = message.conversation
    @response = message.content_attributes['flow_response'].to_h.with_indifferent_access
  end

  def perform
    flow = WhatsappFlow.find_by(id: @response[:flow_id])
    return if flow.blank?

    mappings = flow.field_mappings.to_h.with_indifferent_access
    apply_fields(mappings[:fields].to_h)
    apply_labels(Array(mappings[:labels]))
  end

  private

  def apply_fields(fields)
    conversation_attrs = {}
    contact_attrs = {}
    @response[:fields].to_a.each do |field|
      mapping = fields[field[:name]]
      next if mapping.blank? || field[:value].blank?

      target = mapping[:model].to_s == 'contact' ? contact_attrs : conversation_attrs
      target[mapping[:key]] = cast(field, mapping)
    end
    merge_attributes(@conversation, conversation_attrs)
    merge_attributes(@conversation.contact, contact_attrs)
  end

  def merge_attributes(record, attrs)
    return if attrs.empty? || record.blank?

    record.update!(custom_attributes: record.custom_attributes.to_h.merge(attrs))
  end

  # O tipo do atributo manda: número vira número, caixa de seleção vira
  # booleano, o resto fica com o valor legível (o título da opção, não o id).
  def cast(field, mapping)
    model = mapping[:model].to_s == 'contact' ? 'contact_attribute' : 'conversation_attribute'
    definition = @conversation.account.custom_attribute_definitions.find_by(attribute_key: mapping[:key], attribute_model: model)
    case definition&.attribute_display_type
    when 'number' then field[:value].to_s.tr(',', '.').to_f
    when 'checkbox' then field[:raw] == true || field[:raw].to_s == 'true'
    else field[:value]
    end
  end

  # Só etiquetas que a conta tem: uma etiqueta inventada pelo modelo apareceria
  # na conversa sem existir em lugar nenhum do painel.
  def apply_labels(titles)
    existing = @conversation.account.labels.where(title: titles).pluck(:title)
    @conversation.add_labels(existing) if existing.any?
  end
end
