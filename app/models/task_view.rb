# == Schema Information
#
# Table name: task_views
#
#  id         :bigint           not null, primary key
#  account_id :bigint           not null
#  user_id    :bigint
#  name       :string           not null
#  filters    :jsonb            not null, default {}
#  position   :integer          not null, default 0
#  is_default :boolean          not null, default false
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes:
#   index_task_views_on_account_id_and_user_id
#   index_task_views_on_account_id_and_position
#
class TaskView < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validate  :default_unique_per_owner, if: :is_default?

  scope :shared,   -> { where(user_id: nil) }
  scope :owned_by, ->(user_id) { where(user_id: user_id) }
  # Views visible to the user: their own + shared. Admins get
  # everything via the policy; this scope drives the index payload.
  scope :visible_to, lambda { |user_id|
    where('user_id IS NULL OR user_id = ?', user_id).order(position: :asc, created_at: :asc)
  }

  def push_event_data
    {
      id: id,
      account_id: account_id,
      user_id: user_id,
      name: name,
      filters: filters || {},
      position: position,
      is_default: is_default,
      shared: user_id.nil?,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  # Hard-cap one default per (account, user) tuple. `is_default=true`
  # rows for shared views (user_id IS NULL) also collapse to a single
  # row so the dashboard always has one obvious starting view.
  def default_unique_per_owner
    existing = TaskView.where(account_id: account_id, user_id: user_id, is_default: true)
    existing = existing.where.not(id: id) if persisted?
    errors.add(:is_default, 'is already taken for this owner') if existing.exists?
  end
end
