# UniverZAP: an order from the workspace's store, kept as the store last
# described it (Woocommerce::OrderImporter upserts it from webhooks, the
# backfill and the poller). The contact is the customer matched by phone or
# e-mail; the customer sheet and the spend metrics read from here.
# == Schema Information
#
# Table name: store_orders
#
#  id                   :bigint           not null, primary key
#  currency             :string           default("BRL")
#  customer_email       :string
#  customer_external_id :string
#  customer_name        :string
#  customer_phone       :string
#  items                :jsonb            not null
#  number               :string
#  paid_at              :datetime
#  payment_method       :string
#  payment_method_title :string
#  payment_url          :string
#  placed_at            :datetime
#  status               :string           not null
#  store_updated_at     :datetime
#  total                :decimal(12, 2)   default(0.0), not null
#  tracking             :jsonb            not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  contact_id           :bigint
#  external_id          :string           not null
#  store_connection_id  :bigint           not null
#
# Indexes
#
#  index_store_orders_on_account_id                           (account_id)
#  index_store_orders_on_contact_id                           (contact_id)
#  index_store_orders_on_connection_and_customer              (store_connection_id,customer_external_id)
#  index_store_orders_on_contact_id_and_placed_at             (contact_id,placed_at)
#  index_store_orders_on_store_connection_id                  (store_connection_id)
#  index_store_orders_on_store_connection_id_and_external_id  (store_connection_id,external_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (store_connection_id => store_connections.id)
#
class StoreOrder < ApplicationRecord
  PAID_STATUSES = %w[processing completed].freeze

  belongs_to :account
  belongs_to :store_connection
  belongs_to :contact, optional: true

  validates :external_id, :status, presence: true
  validates :external_id, uniqueness: { scope: :store_connection_id }

  scope :recent_first, -> { order(placed_at: :desc, id: :desc) }
  scope :paid, -> { where(status: PAID_STATUSES) }

  # Spend metrics for the customer sheet: only paid orders count as spend.
  def self.metrics_for(contact)
    paid = where(contact: contact).paid
    count = paid.count
    total = paid.sum(:total)
    {
      orders_count: count,
      total_spent: total.to_f,
      average_ticket: count.zero? ? 0.0 : (total / count).round(2).to_f,
      last_order_at: where(contact: contact).maximum(:placed_at)
    }
  end
end
