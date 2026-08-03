# Creating, promoting and rolling back the instructions the agent runs on.
#
# The first version of any agent is a verbatim copy of what it already runs, so
# adopting versioning changes nothing about how it answers. Everything after
# that is an explicit, reversible act with a record of what it was built from.
class Ai::PromptVersionService
  class NotPromotable < StandardError; end
  class NothingToRollBackTo < StandardError; end

  def initialize(assistant:, user: nil)
    @assistant = assistant
    @user = user
  end

  # A draft seeded from what is live today plus everything reviewers have taught
  # since: ⭐ examples become few-shots, tone corrections become guidance.
  def create_draft(system_prompt: nil, few_shots: nil)
    Ai::PromptVersion.create!(
      ai_assistant: @assistant, account: @assistant.account, created_by: @user,
      version: next_version, status: 'draft',
      system_prompt: system_prompt.presence || current_prompt,
      few_shots: few_shots || collected_few_shots,
      learnings: collected_learning_ids
    )
  end

  # Promotion is a swap, not an edit: the outgoing version is archived intact so
  # rollback is one click and the log keeps pointing at a version that still
  # exists.
  def promote!(version)
    policy = Ai::PromotionPolicy.new(version: version)
    raise NotPromotable, policy.report.to_json unless policy.promotable?

    swap_live!(version, policy.report[:win_rate])
  end

  # Escape hatch for a promotion that looked good in the lab and is not holding
  # up in production. Deliberately NOT gated on the policy: the whole value of
  # rollback is that it works when everything else is going wrong.
  def rollback!
    previous = @assistant.prompt_versions.where(status: 'archived').order(promoted_at: :desc).first
    raise NothingToRollBackTo, 'no archived version to return to' if previous.blank?

    swap_live!(previous, previous.win_rate)
  end

  private

  def swap_live!(version, win_rate)
    Ai::PromptVersion.transaction do
      @assistant.prompt_versions.live.where.not(id: version.id)
                .update_all(status: 'archived', archived_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      version.update!(status: 'live', promoted_at: Time.current, win_rate: win_rate)
    end
    version
  end

  def current_prompt
    @assistant.prompt_versions.live.first&.system_prompt.presence || @assistant.system_prompt
  end

  # Sequential and human-readable, because it appears on every log row and gets
  # read out loud in a postmortem.
  def next_version
    highest = @assistant.prompt_versions.pluck(:version)
                        .filter_map { |v| v[/\d+/]&.to_i }.max || 0
    "v#{highest + 1}"
  end

  # Replies a human marked ⭐, paired with the question that produced them.
  # Capped and newest-first: past a handful the model starts reciting the
  # examples instead of answering the customer.
  def collected_few_shots
    @assistant.response_feedbacks.exemplars.includes(:ai_invocation)
              .order(created_at: :desc).limit(Ai::PromptVersion::MAX_FEW_SHOTS)
              .filter_map { |feedback| few_shot_from(feedback) }
  end

  def few_shot_from(feedback)
    invocation = feedback.ai_invocation
    answer = feedback.corrected_text.presence || invocation&.ai_response
    return nil if invocation&.user_message.blank? || answer.blank?

    { 'question' => invocation.user_message.to_s, 'answer' => answer.to_s }
  end

  # Everything the reviewers said that is NOT already live as knowledge: tone
  # corrections. A version can then explain itself as "built from these".
  def collected_learning_ids
    @assistant.response_feedbacks.corrections.where(reason: 'tom_inadequado', applied_at: nil).pluck(:id)
  end
end
