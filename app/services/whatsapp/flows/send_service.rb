# Manda um Flow numa conversa, como mensagem do painel.
#
# Passa pelo MessageBuilder de propósito: a mensagem aparece na linha do tempo
# e vai para o WhatsApp pelo mesmo caminho de qualquer resposta, onde o
# provider Cloud reconhece `content_attributes.whatsapp_flow` e monta o
# interativo `type: flow`. Fora da janela de 24 h o envio falha como qualquer
# mensagem de sessão: Flow livre só existe dentro de conversa aberta.
class Whatsapp::Flows::SendService
  def initialize(flow:, conversation:, text:, cta:, sender: nil)
    @flow = flow
    @conversation = conversation
    @text = text
    @cta = cta
    @sender = sender
  end

  def perform
    Messages::MessageBuilder.new(@sender, @conversation, message_params).perform
  end

  private

  def message_params
    {
      content: @text,
      message_type: 'outgoing',
      content_type: 'form',
      content_attributes: { items: items, whatsapp_flow: flow_attributes }
    }
  end

  # Os campos do formulário, no formato que a bolha `form` do painel já conhece
  # (e que o validador de content_attributes exige).
  def items
    @flow.field_labels.map { |name, label| { name: name, label: label, type: 'text' } }
  end

  def flow_attributes
    {
      id: @flow.id,
      meta_flow_id: @flow.meta_flow_id,
      cta: @cta.to_s.strip.first(20),
      mode: @flow.send_mode,
      screen: @flow.flow_json.dig('screens', 0, 'id')
    }
  end
end
