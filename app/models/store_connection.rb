# UniverZAP: the shop an e-commerce workspace sells through (WooCommerce for
# now). Holds the REST keys the connector reads orders with and the secret the
# store signs its webhooks with; all three are encrypted at rest. One per
# account.
# == Schema Information
#
# Table name: store_connections
#
#  id              :bigint           not null, primary key
#  consumer_key    :string           not null
#  consumer_secret :string           not null
#  last_error      :string
#  last_synced_at  :datetime
#  platform        :string           default("woocommerce"), not null
#  status          :integer          default("connected"), not null
#  store_url       :string           not null
#  webhook_ids     :jsonb            not null
#  webhook_secret  :string           not null
#  webhook_token   :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_store_connections_on_account_id     (account_id) UNIQUE
#  index_store_connections_on_webhook_token  (webhook_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class StoreConnection < ApplicationRecord
  PLATFORMS = %w[woocommerce].freeze

  belongs_to :account
  has_many :store_orders, dependent: :delete_all

  enum status: { connected: 0, failing: 1 }

  encrypts :consumer_key, :consumer_secret, :webhook_secret if Chatwoot.encryption_configured?

  validates :platform, inclusion: { in: PLATFORMS }
  validates :store_url, :consumer_key, :consumer_secret, presence: true
  validates :account_id, uniqueness: true

  before_validation :generate_secrets, on: :create

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/woocommerce/#{webhook_token}"
  end

  private

  def generate_secrets
    self.webhook_token ||= SecureRandom.urlsafe_base64(24)
    self.webhook_secret ||= SecureRandom.hex(32)
  end
end
