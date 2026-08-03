# Money the agent can be credited with.
#
# This is the number that justifies the credit top-up. Without it the module
# only ever reports cost, and every cost with no revenue beside it looks
# expensive no matter how well the thing works.
#
# Deliberately an explicit ledger rather than a derived query. Attribution is a
# claim about causation, and a claim about causation has to be auditable: who
# said this sale came from the agent, when, and against which conversation.
class CreateAiRevenueEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_revenue_events do |t|
      t.references :ai_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint :conversation_id
      t.bigint :contact_id
      t.bigint :ai_lead_opportunity_id

      # agendamento | assinatura | pedido | recuperado
      t.string :source, null: false
      t.decimal :amount_brl, precision: 12, scale: 2, default: 0.0, null: false
      t.datetime :occurred_at, null: false
      # Order id, booking id, checkout id. Unique per account so the same sale
      # posted twice by a retrying integration is counted once.
      t.string :external_ref
      # 'operator' when a human marked the lead won, 'integration' when an
      # external system posted it, 'agent' when the agent itself did the write.
      t.string :recorded_by, null: false, default: 'operator'
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :ai_revenue_events, %i[ai_assistant_id occurred_at]
    add_index :ai_revenue_events, %i[account_id external_ref], unique: true,
                                                               where: 'external_ref IS NOT NULL'
    add_index :ai_revenue_events, :conversation_id
  end
end
