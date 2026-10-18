class Vertical < ApplicationRecord
  has_many :vertical_statuses, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :vertical

  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name, presence: true
end
