# Per-agent opt-in "human-like reply" behaviors, all default OFF:
#   split_messages  — break one reply into several natural messages
#   reply_marking   — quote (in_reply_to) the customer's question when answering it
#   voice_replies   — answer with a voice note when the customer asks for audio
#
# One jsonb column instead of three booleans on purpose: migrations are applied
# by hand on prod, so every future toggle should ship without a new migration.
class AddBehaviorFlagsToAiAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_assistants, :behavior_flags, :jsonb, null: false, default: {}
  end
end
