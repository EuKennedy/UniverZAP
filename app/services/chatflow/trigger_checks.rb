# Se uma mensagem recebida casa com o gatilho de um fluxo. Incluído no
# Chatflow::EngineService (usa @message e @conversation dele).
module Chatflow::TriggerChecks
  private

  # webhook flows are started externally (POST /chatflows/:id/run), so an
  # inbound message never auto-matches them. Gatilhos de evento (etiqueta,
  # data, lista) também não: eles começam pelo Chatflow::TriggerDispatcher.
  TRIGGER_CHECKS = {
    'on_first_message' => :first_message_trigger?,
    'keyword' => :keyword_hit?,
    'any_message' => :any_message?,
    'ad_referral' => :ad_message?,
    'recurring_customer' => :recurring_customer?,
    'broadcast_reply' => :broadcast_reply?
  }.freeze

  def trigger_matches?(chatflow)
    check = TRIGGER_CHECKS[chatflow.trigger_type]
    check ? send(check, chatflow) : false
  end

  def any_message?(_chatflow)
    true
  end

  # Once per conversation, decided from the data (a previous conversation that
  # ended), not from the label: the conversation.created job may still be running.
  def recurring_customer?(_chatflow)
    first_inbound_message? && Conversations::RecurringCustomerService.recurring?(@conversation)
  end

  # The parsed attribute is written by AdReferralListener, which may still be
  # running when this job starts; the raw text is the same signal either way.
  def ad_message?(_chatflow = nil)
    @message.content_attributes['ad_referral'].present? ||
      Conversations::AdReferralService.ad_message?(@message.content)
  end

  # The first-message trigger fires on the conversation's first inbound
  # message. A `cooldown` restart rule lets it fire again once enough hours
  # have passed since the last run — for recurring touchpoints.
  def first_message_trigger?(chatflow)
    return true if first_inbound_message?

    restart = chatflow.trigger_config['restart'] || {}
    return false unless restart['mode'] == 'cooldown'

    cooldown_elapsed?(chatflow, restart['hours'])
  end

  def cooldown_elapsed?(chatflow, hours)
    window = (hours.to_i.positive? ? hours.to_i : 24).hours
    last_run = chatflow.executions.where(conversation_id: @conversation.id).maximum(:updated_at)
    last_run.nil? || last_run < window.ago
  end

  def first_inbound_message?
    @conversation.messages.incoming.where.not(id: @message.id).none?
  end

  # A PRIMEIRA resposta a um disparo recente (mesma janela de 7 dias que o
  # relatório do disparo usa para "respondeu"). O listener das agendadas pode
  # já ter carimbado `replied_at` com esta mesma mensagem — isso ainda conta.
  def broadcast_reply?(chatflow)
    scope = BroadcastRecipient.where(contact_id: @conversation.contact_id, status: %i[sent delivered read])
                              .where(sent_at: ScheduledMessageListener::REPLY_WINDOW.ago..@message.created_at)
                              .where('replied_at IS NULL OR replied_at >= ?', @message.created_at - 1.second)
    scope = scope.where(broadcast_id: chatflow.trigger_broadcast_ids) if chatflow.trigger_broadcast_ids.any?
    scope.exists?
  end

  def keyword_hit?(chatflow)
    body = @message.content.to_s.downcase
    chatflow.keywords.any? { |keyword| body.include?(keyword) }
  end
end
