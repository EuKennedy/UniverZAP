class CreateUnivercartConnectTables < ActiveRecord::Migration[7.1]
  def change
    # 1:1 com cada subscription Univercart. PK = external_user_id (uuid Univercart, estável).
    # NUNCA use email pra lookups — buyer pode trocar email no perfil.
    create_table :univercart_subscriptions, id: :uuid do |t|
      t.string  :external_user_id, null: false              # subscription_id Univercart
      t.string  :email,            null: false
      t.string  :name,             null: false
      t.string  :document                                    # CPF/CNPJ só dígitos
      t.string  :phone                                       # E.164
      t.string  :role,             null: false               # 'ultra'
      t.string  :status,           null: false, default: 'pending'
      t.string  :product_slug
      t.string  :plan_id
      t.string  :billing_period                              # monthly / yearly
      t.integer :amount_cents
      t.string  :currency,         default: 'BRL'
      t.datetime :valid_until
      t.datetime :cancelled_at
      t.string  :cancel_reason
      t.references :user, type: :integer, foreign_key: true  # nullable até setup
      t.timestamps
      t.index :external_user_id, unique: true
      t.index :email
      t.index [:status, :valid_until]
    end

    # Idempotência: cada event.id Univercart processado UMA vez.
    create_table :univercart_processed_events, id: :string do |t|
      t.string :event_type, null: false
      t.string :subscription_id
      t.datetime :processed_at, null: false
    end
  end
end
