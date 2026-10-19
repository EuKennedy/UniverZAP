class Api::V1::Accounts::VerticalStatusesController < Api::V1::Accounts::BaseController
  before_action :current_account

  MAX_STATUSES = 5
  SELECTION_KEY = 'conversation_bar_labels'.freeze

  def index
    @vertical_key = Current.account.custom_attributes['vertical_template']
    @statuses = selected_titles.present? ? selected_statuses : default_statuses
  end

  # Which labels the conversation list's second row shows, chosen by an admin
  # for the whole account. An empty list goes back to the vertical's default.
  def selection
    authorize Current.account, :update?
    titles = Array(params[:titles]).map(&:to_s).uniq & Current.account.labels.pluck(:title)
    Current.account.custom_attributes[SELECTION_KEY] = titles
    Current.account.save!
    head :no_content
  end

  private

  def selected_titles
    Array(Current.account.custom_attributes[SELECTION_KEY])
  end

  def selected_statuses
    labels = Current.account.labels.where(title: selected_titles).index_by(&:title)
    selected_titles.filter_map do |title|
      label = labels[title]
      next unless label

      { title: title, color: label.color, description: label.description, count: label_count(title) }
    end
  end

  def default_statuses
    return [] if @vertical_key.blank?

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
