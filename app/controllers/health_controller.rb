# Public health probe. Stays light by default so liveness checks don't
# perform expensive work. Pass `?detail=1` with a matching `X-Health-Secret`
# header to surface deep diagnostics — never returns user data.
#
# Three modes:
#   GET /health                        → liveness, 200 always (server is up)
#   GET /health?detail=1 (+ secret)    → readiness, 200 / 503 with breakdown
#   GET /health/sidekiq                → quick sidekiq probe, 200 / 503
class HealthController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    payload = base_payload
    if authorized_detail?
      details = detailed_payload
      payload = payload.merge(details)
      status = details[:ok] ? :ok : :service_unavailable
      return render json: payload, status: status
    end
    render json: payload
  end

  # Lightweight Sidekiq readiness for external uptime monitors
  # (Pingdom, BetterStack, etc). No auth needed because the response
  # only carries status booleans, no user data — but it 503s the
  # moment Sidekiq stops dequeuing so the monitor pages on-call.
  def sidekiq
    state = sidekiq_status
    render json: {
      sidekiq: state,
      timestamp: Time.current.iso8601
    }, status: state == 'ok' ? :ok : :service_unavailable
  end

  private

  def base_payload
    {
      status: 'woot',
      ok: true,
      commit: ENV.fetch('SOURCE_COMMIT', ENV.fetch('GIT_COMMIT', 'unknown')),
      version: Chatwoot.config[:version],
      timestamp: Time.current.iso8601
    }
  end

  def detailed_payload
    db = database_status
    redis = redis_status
    sidekiq = sidekiq_status
    {
      uptime_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i,
      database: db,
      redis: redis,
      sidekiq: sidekiq,
      ok: db == 'ok' && redis == 'ok' && sidekiq == 'ok'
    }
  end

  def authorized_detail?
    return false if params[:detail].blank?

    expected = ENV.fetch('HEALTH_DETAIL_SECRET', nil)
    return false if expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      request.headers['X-Health-Secret'].to_s,
      expected
    )
  end

  def database_status
    ActiveRecord::Base.connection.execute('SELECT 1')
    'ok'
  rescue StandardError
    'down'
  end

  def redis_status
    Redis.new(url: ENV.fetch('REDIS_URL', nil)).ping == 'PONG' ? 'ok' : 'down'
  rescue StandardError
    'down'
  end

  # Sidekiq is "ok" when at least one worker process is alive AND the
  # default queue's latency is under 60s. Idle (no workers) or stuck
  # (high latency) both flip the probe to 503 so monitoring fires.
  def sidekiq_status
    stats = Sidekiq::Stats.new
    return 'down' if stats.processes_size.zero?

    Sidekiq::Queue.new('default').latency > 60 ? 'down' : 'ok'
  rescue StandardError
    'unknown'
  end
end
