class UnivercartSubscription < ApplicationRecord
  self.primary_key = :id

  belongs_to :user, optional: true # populado no setup

  STATUSES = %w[pending active suspended cancelled].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :external_user_id, presence: true, uniqueness: true
  validates :role, presence: true

  scope :active, -> { where(status: 'active') }
end
