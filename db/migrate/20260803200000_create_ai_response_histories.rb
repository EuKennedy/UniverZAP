# The capped store behind the Histórico tab. A projection of ai_invocations:
# one row per delivered reply, trimmed on every write to the newest
# KEEP_PER_ASSISTANT rows per agent (see Ai::ResponseHistory), so the table
# stays flat instead of growing with traffic.
#
# Separate from ai_invocations on purpose: the log the A/B lab, ROI and feedback
# read from must keep its full history, and this one — a read-only convenience
# for one screen — must not. Isolating it is what lets it be capped safely.
class CreateAiResponseHistories < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_response_histories do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :conversation_id
      t.bigint :message_id
      t.text :user_message
      t.text :ai_response
      t.string :model
      t.string :auto_flag
      t.float :confidence
      t.decimal :cost_brl, precision: 12, scale: 6, default: 0.0, null: false
      t.float :cost_usd, default: 0.0, null: false
      t.integer :duration_ms, default: 0, null: false
      t.integer :calls, default: 1, null: false
      t.timestamps
    end
    # The read is always "newest N for this agent", and the trim is "everything
    # past newest N for this agent" — both ride this one index.
    add_index :ai_response_histories, %i[ai_assistant_id created_at]
    # One row per delivered reply. A retried turn re-projecting the same message
    # hits this and is absorbed by create_or_find_by instead of duplicating.
    add_index :ai_response_histories, %i[ai_assistant_id message_id], unique: true
  end
end
