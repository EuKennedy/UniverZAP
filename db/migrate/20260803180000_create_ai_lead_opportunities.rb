# Conversations that ended without a sale, scored so someone can decide which
# ones are worth a follow-up.
#
# Without this the module can only report cost. A dashboard that shows what the
# AI spent and nothing about what it brought in makes the AI look expensive
# no matter how well it works.
class CreateAiLeadOpportunities < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_lead_opportunities do |t|
      t.references :ai_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint :contact_id, null: false
      t.bigint :conversation_id

      t.string :interest
      t.decimal :potential_brl, precision: 12, scale: 2, default: 0.0, null: false
      # 0..100. Deterministic signals carry 60 of it and a cheap model reading
      # carries 40: a score built only from a model drifts between runs and
      # costs a call per conversation.
      t.integer :temperature, null: false, default: 0
      t.string :block_reason
      t.string :suggested_action
      t.string :status, null: false, default: 'open'
      t.decimal :won_brl, precision: 12, scale: 2
      t.datetime :last_seen_at, null: false
      t.datetime :followed_up_at
      # Everything the score was built from, so a number nobody can explain
      # never drives a follow-up campaign.
      t.jsonb :signals, default: {}, null: false

      t.timestamps
    end

    add_index :ai_lead_opportunities, %i[ai_assistant_id status temperature]
    # One open opportunity per conversation: re-scoring updates it instead of
    # stacking duplicates in the radar.
    add_index :ai_lead_opportunities, :conversation_id, unique: true,
                                                        where: 'conversation_id IS NOT NULL'
    add_index :ai_lead_opportunities, %i[account_id contact_id]
  end
end
