class CreateAiCreditLedger < ActiveRecord::Migration[7.1]
  # Money columns in this migration use **BRL cents** as the canonical
  # storage unit. Anthropic costs are billed in USD; the conversion to BRL
  # plus the markup live in `Ai::PricingCalculator`, so every code path
  # downstream of this migration speaks in cents-of-real and never floats.
  def change
    add_credit_columns_to_accounts
    create_credit_ledger_table
    seed_initial_balance
  end

  private

  def add_credit_columns_to_accounts
    add_column :accounts, :token_credit_balance_cents_brl, :integer, default: 2_500, null: false
    add_column :accounts, :token_credit_lifetime_purchased_cents_brl, :integer, default: 0, null: false
    # Grace credits are a one-time +10% nudge so the first quota
    # exhaustion never breaks an in-flight conversation. We flip this
    # flag the moment the grant is consumed so subsequent exhaustions
    # block hard.
    add_column :accounts, :token_credit_grace_used, :boolean, default: false, null: false
    add_index :accounts, :token_credit_balance_cents_brl
  end

  def create_credit_ledger_table
    create_table :ai_credit_ledger_entries do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # 'grant'       → free starter credits given on signup
      # 'purchase'    → real money paid via Univercart (or any future gateway)
      # 'grace'       → one-time +10% nudge when free tier exhausts
      # 'consumption' → Claude API call debit
      # 'refund'      → manual or automated reversal
      # 'adjustment'  → super-admin manual change
      t.string :kind, null: false, limit: 16
      # Signed cents: positive = credit, negative = debit. Storing the
      # signed delta keeps `SUM(amount_cents_brl)` the authoritative
      # balance — the column on accounts is just a denormalized cache.
      t.integer :amount_cents_brl, null: false
      t.references :ai_invocation, null: true, foreign_key: true, index: true
      # External gateway identifier for purchases. Marked unique to make
      # webhook retries idempotent once the Univercart integration is
      # wired up in the next iteration.
      t.string :external_payment_id, index: { unique: true, where: 'external_payment_id IS NOT NULL' }
      t.string :description, limit: 200
      t.timestamps
    end
    add_index :ai_credit_ledger_entries, %i[account_id kind created_at]
  end

  def seed_initial_balance
    # Backfill grant entries for existing accounts so the ledger is the
    # source of truth from day one. Safe to run multiple times because
    # of the `find_or_create_by` guard.
    reversible do |dir|
      dir.up do
        # rubocop:disable Rails/SkipsModelValidations
        Account.find_each do |account|
          existing = ActiveRecord::Base.connection.exec_query(
            'SELECT 1 FROM ai_credit_ledger_entries WHERE account_id = $1 AND kind = $2 LIMIT 1',
            'seed_lookup',
            [account.id, 'grant']
          )
          next if existing.any?

          ActiveRecord::Base.connection.exec_insert(
            'INSERT INTO ai_credit_ledger_entries (account_id, kind, amount_cents_brl, description, created_at, updated_at) ' \
            'VALUES ($1, $2, $3, $4, NOW(), NOW())',
            'seed_insert',
            [account.id, 'grant', 2_500, 'Backfill: R$25 free starter credits']
          )
        end
        # rubocop:enable Rails/SkipsModelValidations
      end
    end
  end
end
