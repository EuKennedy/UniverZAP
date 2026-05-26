# Public health probe. Stays light by default so liveness checks don't
# perform expensive work. Pass `?detail=1` with a matching `X-Health-Secret`
# header to surface deep diagnostics — never returns user data.
class HealthController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    payload = base_payload
    payload = payload.merge(detailed_payload) if authorized_detail?
    render json: payload
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
    {
      uptime_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i,
      database: database_status,
      redis: redis_status,
      sidekiq: sidekiq_status
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

  def sidekiq_status
    Sidekiq::Stats.new.processes_size.positive? ? 'ok' : 'idle'
  rescue StandardError
    'unknown'
  end
end
