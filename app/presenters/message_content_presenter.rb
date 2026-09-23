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

    Messages::MarkdownRendererService.new(text, 'Channel::Whatsapp', inbox.channel).render
  end

  private

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
