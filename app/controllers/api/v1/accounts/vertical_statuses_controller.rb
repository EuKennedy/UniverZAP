class Api::V1::Accounts::VerticalStatusesController < Api::V1::Accounts::BaseController
  before_action :current_account

  MAX_STATUSES = 5

  def index
    @vertical_key = Current.account.custom_attributes['vertical_template']
    @statuses = @vertical_key.present? ? pipeline_statuses : []
  end

  private

  def pipeline_statuses
    vertical = Vertical.find_by(key: @vertical_key)
    return [] unless vertical

    vertical.vertical_statuses.where(closes_conversation: false).order(:position).limit(MAX_STATUSES).filter_map do |status|
      next unless Current.account.labels.exists?(title: status.title)

      { title: status.title, color: status.color, description: status.description, count: label_count(status.title) }
    end
  end

  def label_count(title)
    Current.account.conversations.non_groups.open.tagged_with(title).count
  end
end
