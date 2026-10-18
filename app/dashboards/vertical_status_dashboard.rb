require 'administrate/base_dashboard'

class VerticalStatusDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    vertical: Field::BelongsTo,
    title: Field::String,
    color: Field::String,
    description: Field::Text,
    closes_conversation: Field::Boolean,
    position: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id vertical title closes_conversation position].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id vertical title color description closes_conversation position created_at updated_at].freeze
  FORM_ATTRIBUTES = %i[vertical title color description closes_conversation position].freeze

  def display_resource(vertical_status)
    "#{vertical_status.vertical.name} — #{vertical_status.title}"
  end
end
