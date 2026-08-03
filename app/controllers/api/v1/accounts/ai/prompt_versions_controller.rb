# Versions of the instructions an agent runs on, and the gate that decides
# whether a candidate is allowed to answer real customers.
class Api::V1::Accounts::Ai::PromptVersionsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_version, only: %i[show promote stats replay]

  # How many past replies one "run the lab" click re-asks. Small on purpose:
  # every one is a paid Claude call, and twenty duels is the sample the
  # promotion policy needs, not two hundred.
  DEFAULT_REPLAY_BATCH = 10
  MAX_REPLAY_BATCH = 50

  def index
    render json: {
      live: @assistant.live_prompt_version&.push_event_data,
      versions: @assistant.prompt_versions.newest_first.map(&:push_event_data)
    }
  end

  def show
    render json: @version.push_event_data.merge(system_prompt: @version.system_prompt)
  end

  def create
    version = service.create_draft(
      system_prompt: params[:system_prompt], few_shots: params[:few_shots]
    )
    render json: version.push_event_data.merge(system_prompt: version.system_prompt)
  end

  def promote
    render json: service.promote!(@version).push_event_data
  rescue Ai::PromptVersionService::NotPromotable
    render json: { error: 'criteria not met', report: policy_report }, status: :unprocessable_entity
  end

  def rollback
    render json: service.rollback!.push_event_data
  rescue Ai::PromptVersionService::NothingToRollBackTo => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def stats
    render json: policy_report
  end

  # Queues the duels. Returns immediately: the UI polls the comparisons list,
  # because a synchronous batch would hold the request open for a minute.
  def replay
    invocations = replayable.limit(batch_size)
    invocations.each { |invocation| Ai::AbReplayJob.perform_later(invocation.id, @version.id) }
    render json: { queued: invocations.length }
  end

  private

  # Real questions that produced a real answer, newest first. A reply with no
  # question to re-ask cannot be duelled.
  def replayable
    @assistant.invocations.live.where.not(ai_response: nil).where.not(user_message: nil)
              .order(created_at: :desc)
  end

  def batch_size
    (params[:count] || DEFAULT_REPLAY_BATCH).to_i.clamp(1, MAX_REPLAY_BATCH)
  end

  def policy_report
    Ai::PromotionPolicy.new(version: @version).report
  end

  def service
    @service ||= Ai::PromptVersionService.new(assistant: @assistant, user: Current.user)
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def fetch_version
    @version = @assistant.prompt_versions.find(params[:id])
  end
end
