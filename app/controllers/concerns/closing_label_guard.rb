# UniverZAP: accounts whose vertical defines closing statuses (labels flagged
# `closes_conversation`) need a reason when a person resolves a conversation,
# so the funnel ("lead → agendado") can be measured.
#
# Only the endpoints a person clicks through include this guard. Automations
# (automation rules, Kanban, Chatflow, CSAT, AI) resolve through the model and
# never reach these controllers; agent bots are integrations and stay exempt.
module ClosingLabelGuard
  extend ActiveSupport::Concern

  private

  def closing_label_required?
    Current.user.is_a?(User) && Current.account.labels.closing.exists?
  end

  def closing_label_titles
    Current.account.labels.closing.pluck(:title)
  end

  def render_closing_label_required
    render json: { error: I18n.t('conversations.closing_label.required') }, status: :unprocessable_entity
  end
end
