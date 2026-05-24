class UnivercartProcessedEvent < ApplicationRecord
  self.primary_key = :id
  validates :id, presence: true, uniqueness: true
end
