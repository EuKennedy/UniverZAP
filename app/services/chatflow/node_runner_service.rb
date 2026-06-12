# Executes a single node against the live conversation. Every outbound bot
# message is created through Messages::MessageBuilder so it (a) renders in the
# Chatwoot conversation timeline and (b) dispatches to WhatsApp via the
# WAHA/Channel::Api webhook — the same path the Athenas autopilot uses. This
# is what keeps the flow's messages visible inside Chatwoot.
#
# #run returns a symbol the engine uses to decide the next move:
#   :continue — follow the node's `default` edge to the next node
#   :wait     — pause on a menu node until the customer replies
#   :stop     — terminal node; complete the execution
class Chatflow::NodeRunnerService
  def initialize(execution, node)
    @execution = execution
    @node = node
    @conversation = execution.conversation
  end

  def run
    case @node.kind
    when 'send_message' then send_message_node
    when 'send_audio', 'send_media' then send_media_node
    when 'menu' then send_menu_node
    when 'set_label' then apply_labels_node
    when 'end_flow' then :stop
    else :continue
    end
  end

  # Re-prompt the customer when their reply didn't match any menu option.
  def resend_menu
    send_menu
  end

  private

  def send_message_node
    send_message(content: config_text, attachments: attachment_array)
    :continue
  end

  def send_media_node
    send_message(content: config_caption, attachments: attachment_array)
    :continue
  end

  def send_menu_node
    send_menu
    :wait
  end

  def apply_labels_node
    ids = Array(@node.config['label_ids']).map(&:to_i).reject(&:zero?)
    titles = @conversation.account.labels.where(id: ids).pluck(:title)
    @conversation.add_labels(titles) if titles.any?
    :continue
  end

  def send_menu
    send_message(
      content: menu_text,
      content_type: 'input_select',
      content_attributes: { items: menu_items }
    )
  end

  # Native interactive items for capable channels (Chatwoot input_select +
  # WhatsApp buttons/list via the provider formatter).
  def menu_items
    @node.menu_options.map { |o| { 'title' => o['label'], 'value' => o['value'] } }
  end

  # Numbered text fallback baked into the body so the options always reach
  # WhatsApp even when the connector can't render native buttons.
  def menu_text
    lines = @node.menu_options.each_with_index.map { |o, i| "#{i + 1}- #{o['label']}" }
    [config_text, lines.join("\n")].reject(&:blank?).join("\n\n")
  end

  def config_text
    @node.config['text'].to_s
  end

  def config_caption
    @node.config['caption'].to_s
  end

  def attachment_array
    signed_id = @node.config['attachment']
    signed_id.present? ? [signed_id] : nil
  end

  def send_message(content:, attachments: nil, content_type: nil, content_attributes: nil)
    params = { content: content, message_type: 'outgoing' }
    params[:attachments] = attachments if attachments.present?
    params[:content_type] = content_type if content_type.present?
    params[:content_attributes] = content_attributes if content_attributes.present?

    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end
end
