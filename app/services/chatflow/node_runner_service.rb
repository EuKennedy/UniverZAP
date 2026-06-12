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

  HANDLERS = {
    'send_message' => :send_message_node,
    'send_audio' => :send_media_node,
    'send_media' => :send_media_node,
    'menu' => :send_menu_node,
    'set_label' => :apply_labels_node,
    'assign_agent' => :assign_agent_node,
    'add_to_kanban' => :add_to_kanban_node,
    'webhook' => :webhook_node,
    'end_flow' => :end_flow_node
  }.freeze

  def run
    handler = HANDLERS[@node.kind]
    handler ? send(handler) : :continue
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

  def assign_agent_node
    agent_id = @node.config['agent_id']
    team_id = @node.config['team_id']
    assign_agent(agent_id) if agent_id.present?
    assign_team(team_id) if team_id.present?
    :continue
  end

  def assign_agent(agent_id)
    return unless @conversation.account.account_users.exists?(user_id: agent_id)

    @conversation.update!(assignee_id: agent_id)
  end

  def assign_team(team_id)
    return unless @conversation.account.teams.exists?(id: team_id)

    @conversation.update!(team_id: team_id)
  end

  def add_to_kanban_node
    account = @conversation.account
    funnel = account.funnels.find_by(id: @node.config['funnel_id'])
    stage = funnel&.funnel_stages&.find_by(id: @node.config['funnel_stage_id'])
    return :continue if stage.blank?

    task = account.kanban_tasks.create!(funnel: funnel, funnel_stage: stage, title: kanban_title)
    task.conversations << @conversation
    :continue
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[Chatflow add_to_kanban] #{e.message}")
    :continue
  end

  def kanban_title
    @node.config['title'].presence ||
      @conversation.contact&.name.presence ||
      "Conversa ##{@conversation.display_id}"
  end

  def webhook_node
    url = @node.config['url'].to_s
    return :continue if url.blank?

    method = %w[post get put].include?(@node.config['method']) ? @node.config['method'] : 'post'
    HTTParty.public_send(method, url, body: webhook_payload.to_json,
                                      headers: { 'Content-Type' => 'application/json' }, timeout: 8)
    :continue
  rescue StandardError => e
    Rails.logger.warn("[Chatflow webhook] #{e.message}")
    :continue
  end

  def webhook_payload
    {
      conversation_id: @conversation.display_id,
      inbox_id: @conversation.inbox_id,
      flow_id: @execution.chatflow_id,
      contact: {
        name: @conversation.contact&.name,
        phone_number: @conversation.contact&.phone_number
      }
    }
  end

  # Terminal node. Runs optional finish actions (resolve the conversation,
  # apply labels) before completing the execution.
  def end_flow_node
    actions = @node.config['actions'] || {}
    resolve_conversation if actions['resolve']
    end_labels(actions['label_ids'])
    :stop
  end

  def resolve_conversation
    return if @conversation.resolved?

    @conversation.update!(status: :resolved)
  end

  def end_labels(ids)
    label_ids = Array(ids).map(&:to_i).reject(&:zero?)
    return if label_ids.empty?

    titles = @conversation.account.labels.where(id: label_ids).pluck(:title)
    @conversation.add_labels(titles) if titles.any?
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
