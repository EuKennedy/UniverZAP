# The supervision queue: every reply this agent produced, ordered so the ones a
# human should look at come first.
#
# "Produced", not "delivered". A reply the guardrails suppressed never reached a
# customer, and that is exactly the one worth reading — it is the agent trying to
# invent a price. So the universe is every logged call that generated text.
class Ai::ResponseQueueService
  PER_PAGE = 25
  MAX_PER_PAGE = 100
  FILTERS = %w[all flagged unreviewed reviewed].freeze

  def initialize(assistant:, filter: 'all', flag: nil, page: 1, per_page: PER_PAGE)
    @assistant = assistant
    @filter = FILTERS.include?(filter.to_s) ? filter.to_s : 'all'
    @flag = flag.presence
    @page = [page.to_i, 1].max
    @per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
  end

  def perform
    rows = page_scope.to_a
    feedbacks = feedback_by_invocation(rows.map(&:id))
    {
      page: @page, per_page: @per_page, total: scope.count,
      counts: counts, items: rows.map { |row| item(row, feedbacks[row.id]) }
    }
  end

  private

  def scope
    @scope ||= filtered(@assistant.invocations.live.where.not(ai_response: nil))
  end

  def filtered(base)
    base = base.where(auto_flag: @flag) if @flag
    case @filter
    when 'flagged' then base.flagged
    when 'unreviewed' then base.where.missing(:response_feedbacks)
    when 'reviewed' then base.where.associated(:response_feedbacks)
    else base
    end
  end

  # Flag severity first, recency second: the queue is read top-down and a
  # fabricated price must never sit below yesterday's low-confidence note.
  SEVERITY_ORDER = <<~SQL.squish.freeze
    CASE auto_flag
    #{Ai::Invocation::AUTO_FLAGS.each_with_index.map { |flag, i| "WHEN '#{flag}' THEN #{i}" }.join(' ')}
    ELSE #{Ai::Invocation::AUTO_FLAGS.length} END
  SQL

  def page_scope
    scope.reorder(Arel.sql("#{SEVERITY_ORDER} ASC, created_at DESC"))
         .offset((@page - 1) * @per_page).limit(@per_page)
  end

  def counts
    {
      flagged: @assistant.invocations.live.flagged.count,
      unreviewed: @assistant.invocations.live.where.not(ai_response: nil)
                            .where.missing(:response_feedbacks).count
    }
  end

  def feedback_by_invocation(ids)
    return {} if ids.empty?

    Ai::ResponseFeedback.where(ai_invocation_id: ids).index_by(&:ai_invocation_id)
  end

  def item(row, feedback)
    {
      id: row.id, conversation_id: row.conversation_id, message_id: row.message_id,
      created_at: row.created_at.to_i, user_message: row.user_message.to_s,
      ai_response: row.ai_response.to_s, auto_flag: row.auto_flag,
      auto_flags: Array(row.auto_flags), confidence: row.confidence,
      delivery_status: row.delivery_status, handoff: row.handoff,
      model: row.model, duration_ms: row.duration_ms,
      sources: Array(row.chunks_used).pluck('title').compact.uniq,
      feedback: feedback&.push_event_data
    }
  end
end
