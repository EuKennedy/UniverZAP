# Marks the conversation of a customer who is coming back: the contact already
# had at least one conversation cycle that ended, either
#   - in ANOTHER conversation — resolved, or carrying a label that closes
#     conversations (Label.closing, "Resolver com motivo"); or
#   - in THIS conversation — it was resolved before and the contact wrote
#     again after that resolution. This is the shape the WAHA bridge produces:
#     one conversation per contact, reopened on every return.
#
# Same shape as Conversations::AdReferralService:
#   - the conversation gets the `cliente-recorrente` label (created on the
#     account if missing) so lists, filters and the dashboard can split new
#     from returning customers;
#   - the contact gets `recorrente = true` (definition created if missing):
#     the audience of the repurchase reminder;
#   - `conversation.recurring_customer` fires once per conversation so an
#     automation rule or a Chatflow can act on it (priority, assignment,
#     message).
# Idempotent: a conversation that already carries the label is left alone.
class Conversations::RecurringCustomerService
  LABEL = 'cliente-recorrente'.freeze
  ATTRIBUTE = 'recorrente'.freeze
  RESOLVED_EVENT = 'conversation_resolved'.freeze

  def self.recurring?(conversation)
    return false if conversation.contact.blank?

    other_conversation_ended?(conversation) || reopened_after_resolution?(conversation)
  end

  # The status is the source of truth; the closing labels cover conversations
  # that were closed with a reason and reopened since.
  def self.other_conversation_ended?(conversation)
    previous = conversation.contact.conversations.where.not(id: conversation.id)
    return true if previous.resolved.exists?

    closing = conversation.account.labels.closing.pluck(:title)
    closing.any? && previous.tagged_with(closing, on: :labels, any: true).exists?
  end

  # ReportingEventListener writes a `conversation_resolved` event on every
  # resolution (a closing label resolves the conversation too), and it
  # survives the reopening — unlike the status. A resolution older than the
  # most recent message from the contact means the contact came back.
  def self.reopened_after_resolution?(conversation)
    last_contact_message = conversation.messages.incoming.where(private: false).maximum(:created_at)
    return false if last_contact_message.nil?

    conversation.reporting_events.exists?(name: RESOLVED_EVENT, event_end_time: ...last_contact_message)
  end

  # silent: label and stamp without firing the event — for the backfill, where
  # re-running assignment/priority rules on old conversations would be wrong.
  def initialize(conversation, silent: false)
    @conversation = conversation
    @account = conversation.account
    @silent = silent
  end

  def perform
    return if @conversation.label_list.include?(LABEL)
    return unless self.class.recurring?(@conversation)
    return unless label_conversation

    stamp_contact
    return if @silent

    Rails.configuration.dispatcher.dispatch(
      Events::Types::CONVERSATION_RECURRING_CUSTOMER, Time.zone.now,
      conversation: @conversation, contact: @conversation.contact
    )
  end

  # Public for the backfill: a contact whose returning conversation is already
  # closed is still a returning customer, even though nothing gets labelled.
  # Returns true when the contact was stamped now.
  def stamp_contact
    ensure_definition
    contact = @conversation.contact
    return false if contact.custom_attributes[ATTRIBUTE] == true

    contact.update!(custom_attributes: contact.custom_attributes.merge(ATTRIBUTE => true))
    true
  end

  private

  # The check above runs once per incoming message, and a returning contact
  # often sends several in a row: each one lands in its own job. The row lock
  # makes the first job label the conversation and the others see the label,
  # so the event fires once per cycle. A fresh copy is locked because the
  # caller's instance may carry unsaved changes (a just-created conversation
  # does). Returns true when this call labelled.
  def label_conversation
    Conversation.transaction do
      locked = Conversation.lock.find(@conversation.id)
      next false if locked.label_list.include?(LABEL)

      ensure_label
      locked.add_labels([LABEL])
      true
    end
  end

  # The definition makes the attribute show up in the contact sidebar, in
  # filters and as an automation condition. Created once, never overwritten.
  def ensure_definition
    @account.custom_attribute_definitions.find_or_create_by!(attribute_key: ATTRIBUTE, attribute_model: 'contact_attribute') do |record|
      record.attribute_display_name = I18n.t('recurring_customer.attributes.recorrente')
      record.attribute_display_type = 'checkbox'
      record.attribute_description = I18n.t('recurring_customer.attributes.recorrente_description')
    end
  end

  def ensure_label
    @account.labels.find_or_create_by!(title: LABEL) do |label|
      label.color = '#94A3B8'
      label.description = I18n.t('recurring_customer.label_description')
      label.show_on_sidebar = true
    end
  end
end
