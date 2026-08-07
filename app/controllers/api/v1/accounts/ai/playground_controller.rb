# Test sandbox for an Athenas assistant: the operator talks to their own agent
# as if they were a customer, and sees what it answers before a real customer
# does. Administrators only, and always scoped to the current account.
class Api::V1::Accounts::Ai::PlaygroundController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant

  def show
    render json: { transcript: service.transcript }
  end

  # Queues the turn instead of generating it inline: a turn outlives the web
  # request (see Ai::PlaygroundReplyJob). The reply arrives through the
  # transcript, which the UI polls.
  def create
    message = params[:message].to_s.strip
    return render_could_not_create_error('Message is required') if message.blank?
    return render_playground_busy if service.generating?
    return render_rate_limited if rate_limiter.exceeded?

    rate_limiter.record!
    Ai::PlaygroundReplyJob.perform_later(@assistant.id, Current.user.id, message)
    render json: { status: 'queued' }, status: :accepted
  end

  def destroy
    service.reset!
    head :no_content
  end

  private

  # Every turn costs the account real credits, and queueing a second one while
  # the first is still generating produces two replies to interleaved questions
  # — confusing to read and paid for twice. One in flight per sandbox.
  def render_playground_busy
    render json: { status: 'busy', error: I18n.t('errors.ai.playground_busy') }, status: :too_many_requests
  end

  def render_rate_limited
    render json: { status: 'rate_limited', error: I18n.t('errors.ai.playground_rate_limited') },
           status: :too_many_requests
  end

  # Sized for a human testing an agent, not for a load generator: a turn takes
  # 20-40s, so a person cannot legitimately need more than a handful a minute,
  # and each one is billed.
  PLAYGROUND_TURNS_PER_MINUTE = 6

  def rate_limiter
    @rate_limiter ||= Redis::SlidingWindowRateLimiter.new(
      "ATHENAS::PLAYGROUND::RATE::#{@assistant.id}::#{Current.user.id}",
      limit: PLAYGROUND_TURNS_PER_MINUTE,
      window: 60
    )
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  # Scoped through the account association: an assistant id from another tenant
  # raises RecordNotFound instead of leaking.
  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def service
    @service ||= Ai::PlaygroundService.new(account: Current.account, assistant: @assistant, user: Current.user)
  end
end
