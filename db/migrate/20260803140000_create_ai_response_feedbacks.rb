# The human verdict on one agent reply, and what that verdict became.
#
# The guardrails in sprint 1 say "a person should look at this". This table is
# what the person says back, and it is the only input in the module that can
# teach the agent something it did not already have.
class CreateAiResponseFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_response_feedbacks do |t|
      t.references :ai_invocation, null: false, foreign_key: true, index: true
      # Denormalised so the approval rate of an agent is one indexed query and
      # never a join through the log.
      t.references :ai_assistant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint :reviewer_id, null: false

      t.string :rating, null: false
      t.string :reason
      t.text :corrected_text
      # When the correction actually became something the agent uses, and what.
      # Null means recorded but not yet applied: tone corrections wait for a
      # prompt version, and a failed application must stay visible.
      t.datetime :applied_at
      t.bigint :ai_training_id
      t.bigint :ai_intent_id

      t.timestamps
    end

    add_index :ai_response_feedbacks, %i[ai_assistant_id created_at]
    # One verdict per reviewer per reply. Re-rating updates the row instead of
    # stacking votes, so the approval rate cannot be inflated by clicking twice.
    add_index :ai_response_feedbacks, %i[ai_invocation_id reviewer_id], unique: true,
                                                                        name: 'index_ai_feedback_unique_reviewer'
  end
end
