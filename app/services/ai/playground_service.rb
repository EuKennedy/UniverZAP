# Sandbox that lets an operator talk to their own assistant exactly as a
# customer would, BEFORE a real customer does.
#
# Fidelity is the entire point: this runs Ai::AutopilotReplyService, the very
# object the production WhatsApp path runs, over a real Conversation. A
# playground that reimplemented the prompt would be testing a fiction and would
# drift from production the first time either side changed.
#
# The sandbox conversation lives in a per-account hidden inbox and is stamped
# `athenas_sandbox`, so it never shows up next to real customers (see
# Conversation.not_sandbox). Nothing is ever delivered outbound: the reply is
# written straight to the transcript instead of going through the job that
# posts to a channel.
class Ai::PlaygroundService
  SANDBOX_INBOX_NAME = 'Athenas · Teste do agente'.freeze
  SANDBOX_CONTACT_NAME = 'Cliente de teste'.freeze

  def initialize(account:, assistant:, user:)
    @account = account
    @assistant = assistant
    @user = user
  end

  # Returns the reply plus the diagnostics that make this a testing tool rather
  # than a toy: which knowledge it actually used, whether the guardrails had to
  # correct it, how long it took and what it cost.
  def send_message(text)
    conversation = sandbox_conversation
    persist_incoming(conversation, text)
    started_at = Time.zone.now
    service = Ai::AutopilotReplyService.new(conversation: conversation, assistant: @assistant)
    result = service.perform
    reply = persist_outgoing(conversation, result[:content])
    success(reply, service, started_at)
  rescue Ai::AutopilotReplyService::UngroundedClaim
    suppressed(:ungrounded_claim, service, started_at)
  rescue Ai::AutopilotReplyService::LoopSuppressed
    suppressed(:loop_suppressed, service, started_at)
  end

  # Wipes the transcript so the operator can start a clean scenario.
  def reset!
    sandbox_conversation.messages.destroy_all
    sandbox_conversation.update!(additional_attributes: sandbox_stamp)
  end

  def transcript
    sandbox_conversation.messages.reorder(created_at: :asc, id: :asc).map do |message|
      { id: message.id, role: message.incoming? ? 'user' : 'assistant', content: message.content,
        created_at: message.created_at.to_i }
    end
  end

  private

  def success(reply, service, started_at)
    {
      status: 'replied',
      content: reply.content,
      diagnostics: service.playground_diagnostics.merge(
        latency_ms: ((Time.zone.now - started_at) * 1000).to_i,
        cost: last_invocation_cost
      )
    }
  end

  # The guardrails firing is a RESULT, not an error: it tells the operator their
  # knowledge base is missing something the agent was asked for. So this is the
  # case where the diagnostics matter MOST — which passages were retrieved is
  # exactly what lets them fix the gap.
  def suppressed(reason, service, started_at)
    {
      status: reason.to_s,
      content: nil,
      diagnostics: service.playground_diagnostics.merge(
        latency_ms: ((Time.zone.now - started_at) * 1000).to_i,
        cost: last_invocation_cost
      )
    }
  end

  def last_invocation_cost
    invocation = Ai::Invocation.where(account_id: @account.id, conversation_id: sandbox_conversation.id)
                               .reorder(created_at: :desc, id: :desc).first
    return nil if invocation.blank?

    { input_tokens: invocation.input_tokens, output_tokens: invocation.output_tokens, usd: invocation.cost_usd }
  end

  def persist_incoming(conversation, text)
    conversation.messages.create!(
      account_id: @account.id, inbox_id: conversation.inbox_id,
      message_type: :incoming, content: text.to_s.strip, sender: conversation.contact
    )
  end

  # `sender: nil` mirrors production exactly (Ai::AutopilotReplyJob#assistant_user
  # posts with no sender). This is not cosmetic: a sender makes the message look
  # HUMAN-authored, which would turn a price the bot invented on turn 1 into a
  # sanctioned source on turn 2 and silently disable the grounding guard — the
  # playground would then be more permissive than production, which is the one
  # direction a pre-flight test must never fail in. It also keeps sandbox turns
  # out of the account's first-response and reply-time reports.
  def persist_outgoing(conversation, content)
    conversation.messages.create!(
      account_id: @account.id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, content: content.to_s, status: :delivered, sender: nil
    )
  end

  def sandbox_conversation
    @sandbox_conversation ||= @account.conversations
                                      .where("additional_attributes->>'athenas_sandbox_key' = ?", sandbox_key)
                                      .first || create_sandbox_conversation
  end

  # One sandbox per (assistant, operator): two admins testing the same agent
  # must not stomp on each other's transcript.
  def sandbox_key
    "#{@assistant.id}-#{@user.id}"
  end

  def sandbox_stamp
    { 'athenas_sandbox' => true, 'athenas_sandbox_key' => sandbox_key }
  end

  def create_sandbox_conversation
    @account.conversations.create!(
      inbox: sandbox_inbox, contact: sandbox_contact,
      contact_inbox: contact_inbox_for(sandbox_inbox, sandbox_contact),
      additional_attributes: sandbox_stamp
    )
  end

  # find-or-create, retried on the unique index: two admins opening the
  # playground at the same moment would otherwise both miss the lookup and the
  # loser would get a 500 from RecordNotUnique.
  def contact_inbox_for(inbox, contact)
    ContactInbox.find_by(inbox: inbox, contact: contact) ||
      ContactInbox.create!(inbox: inbox, contact: contact, source_id: "athenas-playground-#{contact.id}")
  rescue ActiveRecord::RecordNotUnique
    ContactInbox.find_by!(inbox: inbox, contact: contact)
  end

  # Stamped so contact events can be recognised as sandbox and kept out of the
  # account's webhooks and integrations (a fake customer must not be published
  # as a real new contact).
  def sandbox_contact
    @sandbox_contact ||= @account.contacts.find_by(identifier: 'athenas-playground') ||
                         @account.contacts.create!(
                           name: SANDBOX_CONTACT_NAME, identifier: 'athenas-playground',
                           custom_attributes: { 'athenas_sandbox' => true }
                         )
  rescue ActiveRecord::RecordNotUnique
    @sandbox_contact = @account.contacts.find_by!(identifier: 'athenas-playground')
  end

  # An Api channel with no webhook: it can hold a conversation but has nowhere
  # to deliver to, so a sandbox message physically cannot reach a customer.
  def sandbox_inbox
    @sandbox_inbox ||= @account.inboxes.find_by(name: SANDBOX_INBOX_NAME) ||
                       @account.inboxes.create!(name: SANDBOX_INBOX_NAME, channel: Channel::Api.create!(account: @account))
  end
end
