class Api::V1::Accounts::VerticalStatusesController < Api::V1::Accounts::BaseController
  before_action :current_account

  MAX_STATUSES = 5
  SELECTION_KEY = 'conversation_bar_labels'.freeze

  # The second row of the conversation list. Three sources, in order of
  # precedence: the titles the caller asks for (an agent's personal bar),
  # the labels an admin picked for the whole account, the vertical's default.
  def index
    @vertical_key = Current.account.custom_attributes['vertical_template']
    @statuses = params[:scope] == 'all' ? all_statuses : bar_statuses
  end

  # Every label of the account with its open count, most used first — what
  # the picker shows so choosing is informed, not a guess.
  def catalog
    counts = open_counts_by_label
    @labels = Current.account.labels.order(:title).map do |label|
      { title: label.title, color: label.color, description: label.description, count: counts.fetch(label.title, 0) }
    end
    @labels.sort_by! { |label| [-label[:count], label[:title]] }
  end

  # Which labels the bar shows for the whole account, chosen by an admin.
  # An empty list goes back to the vertical's default.
  def selection
    authorize Current.account, :update?
    titles = Array(params[:titles]).map(&:to_s).uniq & Current.account.labels.pluck(:title)
    Current.account.custom_attributes[SELECTION_KEY] = titles
    Current.account.save!
    head :no_content
  end

  private

  def bar_statuses
    titles = params[:titles].present? ? Array(params[:titles]).map(&:to_s) : selected_titles
    titles.present? ? statuses_for(titles) : default_statuses
  end

  def selected_titles
    Array(Current.account.custom_attributes[SELECTION_KEY])
  end

  def statuses_for(titles)
    labels = Current.account.labels.where(title: titles).index_by(&:title)
    titles.uniq.filter_map do |title|
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

  # Every stage of the vertical, closing ones included: what the customer
  # sheet needs to tell a stage label from any other label.
  def all_statuses
    return [] if @vertical_key.blank?

    vertical = Vertical.find_by(key: @vertical_key)
    return [] unless vertical

    vertical.vertical_statuses.map do |status|
      status.slice(:title, :color, :description, :closes_conversation)
    end
  end

  def label_count(title)
    Current.account.conversations.regular.open.tagged_with(title).count
  end

  # One query for the whole catalog instead of one per label.
  def open_counts_by_label
    Current.account.conversations.regular.open
           .joins(:taggings).joins('INNER JOIN tags ON tags.id = taggings.tag_id')
           .where(taggings: { context: 'labels' })
           .group('tags.name').count
  end
end
