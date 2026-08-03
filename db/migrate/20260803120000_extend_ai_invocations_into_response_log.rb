# Turns `ai_invocations` (pure cost telemetry) into the response log the agent
# module is built on: what the customer asked, what the agent answered, which
# prompt and which knowledge chunks produced it, and whether a guardrail had to
# step in.
#
# One table instead of a separate AgentResponseLog on purpose. A reply that uses
# the scheduling tools bills several Claude calls, and splitting the log would
# force every screen (cost, latency, supervision) to join two tables and decide
# which call "is" the reply. The reply-shaped columns are simply NULL on the
# phases that never face a customer (summary, classifier, rewrite).
class ExtendAiInvocationsIntoResponseLog < ActiveRecord::Migration[7.1]
  # ai_invocations takes a write on every Claude call, so a plain CREATE INDEX
  # would hold ACCESS EXCLUSIVE and stall every reply on the platform for the
  # duration. Concurrent index builds need to run outside a transaction.
  # The ALTER itself stays cheap: in Postgres 11+ adding a column with a
  # non-volatile default is a catalogue-only change, not a table rewrite.
  disable_ddl_transaction!

  def change
    change_table :ai_invocations, bulk: true do |t|
      # Immutable snapshot of the exact system prompt used. Without it the A/B
      # replay cannot reproduce the original condition.
      t.text :system_prompt
      t.text :user_message
      t.text :ai_response
      # [{ title, score, chars }] — which knowledge passages were selected and
      # how they ranked. Bodies are NOT stored: they are re-retrieved on replay,
      # and duplicating up to 6 KB of catalogue per reply would bloat the table
      # for no supervision value.
      t.jsonb :chunks_used, default: [], null: false
      t.string :prompt_version
      # The customer message that triggered this turn. Linking the reply back to
      # its calls used to be a "same conversation, last 5 minutes" guess, which
      # silently swept up rows from a neighbouring turn. This makes it exact.
      t.bigint :trigger_message_id
      # 0..1 self-assessment Claude emits in a <meta> block that is stripped
      # before the text reaches the customer.
      t.float :confidence
      # Highest-severity guardrail hit, denormalised so the supervision queue can
      # sort on an index; the full set lives in auto_flags.
      t.string :auto_flag
      t.jsonb :auto_flags, default: [], null: false
      t.boolean :handoff, default: false, null: false
      # pending -> sent | failed. NULL means this call never had a delivery of
      # its own (a tool-loop iteration, a summary, a suggestion).
      t.string :delivery_status
      # What the operator was actually charged, in BRL. cost_usd stays as the
      # upstream figure; this is the one the ROI panel divides revenue by.
      t.decimal :cost_brl, precision: 12, scale: 6, default: 0.0, null: false
      # Produced in the test playground. These calls cost real money, so they
      # belong in the spend figures, but they must never reach the supervision
      # queue: nobody needs to review an answer given to a fake customer.
      t.boolean :sandbox, default: false, null: false
    end

    # Supervision queue: flagged real replies of one agent, newest first.
    add_index :ai_invocations, %i[ai_assistant_id auto_flag created_at],
              where: 'auto_flag IS NOT NULL AND sandbox = false',
              name: 'index_ai_invocations_on_flag_queue', algorithm: :concurrently
    # "What was generated and never accounted for?" must stay cheap. Partial on
    # 'pending' only: a settled row is never the subject of that question, and
    # indexing every delivered row would tax the hottest write path for nothing.
    add_index :ai_invocations, %i[ai_assistant_id created_at],
              where: "delivery_status = 'pending'",
              name: 'index_ai_invocations_on_undelivered', algorithm: :concurrently
    # Every call of one turn, exactly. This is what replaced the "same
    # conversation, last five minutes" guess when linking a reply to its calls.
    add_index :ai_invocations, :trigger_message_id,
              where: 'trigger_message_id IS NOT NULL', algorithm: :concurrently
  end
end
