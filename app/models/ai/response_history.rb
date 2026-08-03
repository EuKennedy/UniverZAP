# A rolling window of the agent's most recent delivered replies — the data
# behind the Histórico tab. It is a projection of ai_invocations, not the source
# of truth: the A/B lab, ROI and feedback still read the full log. This table
# exists only so the screen read stays a flat "last N rows" no matter how much
# traffic the agent has served over its lifetime.
#
# Written (and trimmed) by Ai::ResponseHistoryRecorder on every delivered reply.
class Ai::ResponseHistory < ApplicationRecord
  self.table_name = 'ai_response_histories'

  # More than this is unusable to a human scrolling the screen and pointless to
  # keep — the log has the rest. On every write the overflow is dropped, so the
  # table never grows with traffic.
  KEEP_PER_ASSISTANT = 100

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  scope :recent, -> { order(created_at: :desc) }

  # Drops everything past the newest KEEP rows for one agent. Cheap: the
  # (ai_assistant_id, created_at) index turns the keep-set into an index range
  # scan and the delete only touches the overflow.
  def self.trim!(ai_assistant_id, keep: KEEP_PER_ASSISTANT)
    overflow = where(ai_assistant_id: ai_assistant_id).recent.offset(keep).ids
    where(id: overflow).delete_all if overflow.any?
  end
end
