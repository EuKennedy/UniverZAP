class VerticalStatus < ApplicationRecord
  belongs_to :vertical, inverse_of: :vertical_statuses

  validates :title, presence: true
end
