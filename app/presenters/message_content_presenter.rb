class MessageContentPresenter < SimpleDelegator
  def outgoing_content
    Messages::MarkdownRendererService.new(
      content_with_survey_link,
      conversation.inbox.channel_type,
      conversation.inbox.channel
    ).render
  end

  # Webhook cru é o certo para quem consome webhook: integração de terceiro quer
  # o markdown como foi escrito. Mas a caixa que o assistente do WAHA cria é
  # Channel::Api — genérica — e do outro lado tem WhatsApp, que não entende
  # markdown. Sem tradutor, `**negrito**` chega com os asteriscos literais na
  # conversa do cliente, e foi exatamente isso que o operador viu.
  #
  # Só a caixa marcada como WAHA entra nessa exceção: formatar todo Channel::Api
  # como WhatsApp quebraria as integrações que esperam o texto como está.
  def webhook_content
    text = content_with_survey_link
    return Messages::WebhookContentNormalizer.normalize(text) unless waha_channel?

    signed(Messages::MarkdownRendererService.new(text, 'Channel::Whatsapp', inbox.channel).render)
  end

  private

  # O nome de quem ESCREVEU a mensagem, em negrito do WhatsApp (UM asterisco —
  # dois chegam literais), acima do texto. Assina o autor, nao o atribuido: um
  # supervisor que responde fora da atribuicao assinaria o nome de outra pessoa
  # e o cliente nao teria como saber.
  #
  # Desligado por padrao. Sessao criada pelo app Chatwoot do WAHA ja assina do
  # lado de la, e os dois ligados mandam o nome duas vezes.
  def signed(text)
    return text if text.blank? || private? || !outgoing?
    return text unless agent_signature_enabled?

    name = sender.is_a?(User) ? sender.available_name : nil
    name.present? ? "*#{name}*\n#{text}" : text
  end

  def agent_signature_enabled?
    conversation.inbox.channel.additional_attributes.to_h['agent_name_signature'].present?
  end

  def waha_channel?
    channel = conversation.inbox.channel
    channel.is_a?(Channel::Api) && channel.additional_attributes.to_h['source'] == 'waha'
  end

  def content_with_survey_link
    if should_append_survey_link?
      survey_link = survey_url(conversation.uuid)
      custom_message = inbox.csat_config&.dig('message')
      custom_message.present? ? "#{custom_message} #{survey_link}" : I18n.t('conversations.survey.response', link: survey_link)
    else
      content
    end
  end

  def should_append_survey_link?
    input_csat? && !inbox.web_widget?
  end

  def survey_url(conversation_uuid)
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{conversation_uuid}"
  end
end
