class Ai::Training < ApplicationRecord
  self.table_name = 'ai_trainings'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  SOURCE_TYPES = %w[text url file faq].freeze
  CATEGORIES = %w[base catalog policies sales faq support].freeze
  STATUSES = %w[pending processing ready error].freeze

  validates :title, presence: true, length: { maximum: 180 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_save :compute_char_count

  scope :ready, -> { where(status: 'ready') }
  scope :by_category, ->(category) { where(category: category) }

  def push_event_data
    {
      id: id,
      title: title,
      source_type: source_type,
      category: category,
      status: status,
      char_count: char_count,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def compute_char_count
    self.char_count = content.to_s.length
  end
end
