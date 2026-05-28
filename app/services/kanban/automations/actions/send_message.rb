# Send a message to every conversation attached to the task.
# Params:
#   content (String, required) — supports `{{contact_name}}`, `{{task_title}}`,
#                                `{{stage_name}}`, `{{funnel_name}}` placeholders
#   message_type (String, default 'outgoing') — 'outgoing' | 'template'
#   private (Boolean, default false) — internal note vs customer-visible
class Kanban::Automations::Actions::SendMessage < Kanban::Automations::Actions::Base
  PLACEHOLDERS = {
    '{{contact_name}}' => ->(task, conv) { conv.contact&.name || task.contacts.first&.name || '' },
    '{{task_title}}' => ->(task, _conv) { task.title.to_s },
    '{{task_url}}' => ->(task, _conv) { Kanban::Automations::Actions::SendMessage.kanban_task_url(task) },
    '{{stage_name}}' => ->(task, _conv) { task.funnel_stage&.name.to_s },
    '{{funnel_name}}' => ->(task, _conv) { task.funnel&.name.to_s }
  }.freeze

  def self.kanban_task_url(task)
    base = ENV.fetch('FRONTEND_URL', '')
    return '' if base.blank?

    "#{base}/app/accounts/#{task.account_id}/kanban/funnels/#{task.funnel_id}?task=#{task.id}"
  end

  private

  def perform!
    raw_content = required_param!(:content)
    is_private = ActiveModel::Type::Boolean.new.cast(params[:private])
    type = params[:message_type].presence || 'outgoing'

    targets = conversation_targets
    raise ExecutionError, 'no conversations attached to task' if targets.empty?

    deliver_to_targets(targets, raw_content, type, is_private)
  end

  def deliver_to_targets(targets, raw_content, type, is_private)
    targets.each do |conversation|
      content = render_content(raw_content, conversation)
      next if content.blank?

      Messages::MessageBuilder.new(
        nil,
        conversation,
        content: content,
        message_type: type,
        private: is_private
      ).perform
    end
  end

  def conversation_targets
    task.conversations.where.not(status: Conversation.statuses[:resolved]).to_a
  end

  def render_content(template, conversation)
    PLACEHOLDERS.reduce(template) do |acc, (token, resolver)|
      acc.gsub(token) { resolver.call(task, conversation).to_s }
    end
  end
end
