# Marks the conversation of a customer who is coming back: the contact already
# had at least one other conversation that ended — resolved, or carrying a
# label that closes conversations (Label.closing, "Resolver com motivo").
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

  # The status is the source of truth; the closing labels cover conversations
  # that were closed with a reason and reopened since.
  def self.recurring?(conversation)
    contact = conversation.contact
    return false if contact.blank?

    previous = contact.conversations.where.not(id: conversation.id)
    return true if previous.resolved.exists?

    closing = conversation.account.labels.closing.pluck(:title)
    closing.any? && previous.tagged_with(closing, on: :labels, any: true).exists?
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

    ensure_label
    @conversation.add_labels([LABEL])
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
