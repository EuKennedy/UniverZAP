# UniverZAP: a group of inboxes under "Canais" in the sidebar. Every inbox
# lands in its explicit group (inboxes.inbox_group_id) or else in the group of
# its kind; the dashboard shows a default group for a kind nobody created.
class InboxGroup < ApplicationRecord
  KINDS = %w[whatsapp instagram facebook email website telegram line sms tiktok twitter api].freeze

  belongs_to :account
  has_many :inboxes, dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }
  validates :kind, inclusion: { in: KINDS }, uniqueness: { scope: :account_id }, allow_nil: true

  # The groups travel with the inbox list the dashboard caches, and deleting
  # one moves inboxes without touching them (the foreign key nullifies).
  after_commit -> { account.update_cache_key('inbox') }
end
