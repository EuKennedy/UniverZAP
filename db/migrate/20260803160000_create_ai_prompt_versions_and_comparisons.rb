# Versioning for the part of the agent a human writes, plus the duel that
# decides whether a new version is actually better.
#
# Today the agent's instructions live in a single mutable column on
# ai_assistants. Editing it is a silent, irreversible production change: nobody
# can tell which replies came from which wording, and a change that made things
# worse looks exactly like a change that made things better.
class CreateAiPromptVersionsAndComparisons < ActiveRecord::Migration[7.1]
  def change
    create_versions
    create_comparisons
  end

  def create_versions
    create_table :ai_prompt_versions do |t|
      t.references :ai_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :version, null: false
      # Immutable once promoted: this is what the log's prompt_version points at.
      t.text :system_prompt
      # [{ question, answer }] taken from replies a human marked ⭐. Tone is
      # taught by example, so this is where a tone correction actually lands.
      t.jsonb :few_shots, default: [], null: false
      # ids of the feedbacks this version incorporated, so a version can explain
      # itself: "built from these 11 corrections".
      t.jsonb :learnings, default: [], null: false
      t.string :status, null: false, default: 'draft'
      t.float :win_rate
      t.datetime :promoted_at
      t.datetime :archived_at
      t.bigint :created_by_id

      t.timestamps
    end
    add_index :ai_prompt_versions, %i[ai_assistant_id version], unique: true
    # At most one live version per agent, enforced by the database rather than
    # by hope: two live versions would make "which prompt answered this?"
    # unanswerable exactly when it matters.
    add_index :ai_prompt_versions, :ai_assistant_id, unique: true,
                                                     where: "status = 'live'",
                                                     name: 'index_ai_prompt_versions_one_live'
  end

  def create_comparisons
    create_table :ai_ab_comparisons do |t|
      # Column A is never regenerated: it is the reply the customer actually
      # received, a historical fact read straight from the log.
      t.references :ai_invocation, null: false, foreign_key: true
      t.references :ai_prompt_version, null: false, foreign_key: true
      t.references :ai_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true

      t.text :response_b
      # tokens, cost, latency, chunks, confidence for the candidate.
      t.jsonb :telemetry_b, default: {}, null: false
      t.string :winner
      # B asserted a value that exists in no sanctioned source. One of these
      # blocks promotion outright, no matter how good the win rate looks.
      t.boolean :critical_loss, default: false, null: false
      t.bigint :reviewer_id

      t.timestamps
    end
    add_index :ai_ab_comparisons, %i[ai_prompt_version_id winner]
    # One duel per (reply, candidate): replaying the same question twice would
    # let the same comparison be voted on twice.
    add_index :ai_ab_comparisons, %i[ai_invocation_id ai_prompt_version_id], unique: true,
                                                                            name: 'index_ai_ab_unique_duel'
  end
end
