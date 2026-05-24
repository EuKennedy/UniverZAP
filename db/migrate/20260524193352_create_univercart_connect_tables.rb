class CreateUnivercartConnectTables < ActiveRecord::Migration[7.1]
  def change
    create_subscriptions_table
    create_processed_events_table
  end

  private

  # 1:1 com cada subscription Univercart. PK = external_user_id (uuid Univercart, estável).
  # NUNCA use email pra lookups — buyer pode trocar email no perfil.
  # rubocop:disable Metrics/MethodLength
  def create_subscriptions_table
    create_table :univercart_subscriptions, id: :uuid do |t|
      t.string :external_user_id, null: false
      t.string :email, null: false
      t.string :name, null: false
      t.string :document
      t.string :phone
      t.string :role, null: false
      t.string :status, null: false, default: 'pending'
      t.string :product_slug
      t.string :plan_id
      t.string :billing_period
      t.integer :amount_cents
      t.string :currency, default: 'BRL'
      t.datetime :valid_until
      t.datetime :cancelled_at
      t.string :cancel_reason
      t.references :user, type: :integer, foreign_key: true
      t.timestamps
      t.index :external_user_id, unique: true
      t.index :email
      t.index %i[status valid_until]
    end
  end
  # rubocop:enable Metrics/MethodLength

  # Idempotência: cada event.id Univercart processado UMA vez.
  def create_processed_events_table
    create_table :univercart_processed_events, id: :string do |t|
      t.string :event_type, null: false
      t.string :subscription_id
      t.datetime :processed_at, null: false
      t.timestamps
    end
  end
end
