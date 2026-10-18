require 'administrate/base_dashboard'

class VerticalDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    key: Field::String,
    name: Field::String,
    description: Field::Text,
    vertical_statuses: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id key name].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id key name description vertical_statuses created_at updated_at].freeze
  FORM_ATTRIBUTES = %i[key name description].freeze

  def display_resource(vertical)
    vertical.name
  end
end
