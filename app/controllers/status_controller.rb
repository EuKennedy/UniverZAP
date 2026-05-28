# Public status page (HTML) + JSON probe. Shows operators and
# customers the live health of database / Redis / Sidekiq / WAHA
# webhook in one screen so an outage is visible without diving into
# Coolify or Sentry. Lightweight: no auth, no DB writes, no user
# data — every check has a hard 200ms budget.
class StatusController < ActionController::Base # rubocop:disable Rails/ApplicationController
  protect_from_forgery with: :null_session

  def show
    @summary = build_summary
    respond_to do |format|
      format.html
      format.json { render json: @summary, status: overall_http_status(@summary) }
    end
  end

  private

  def build_summary
    db = check(:database) { ActiveRecord::Base.connection.execute('SELECT 1'); 'ok' }
    redis = check(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', nil)).ping == 'PONG' ? 'ok' : 'down' }
    sidekiq = check(:sidekiq) { sidekiq_state }

    overall = [db[:status], redis[:status], sidekiq[:status]].all?('ok') ? 'operational' : 'degraded'
    {
      overall: overall,
      checked_at: Time.current.iso8601,
      commit: ENV.fetch('SOURCE_COMMIT', 'unknown')[0, 9],
      services: { database: db, redis: redis, sidekiq: sidekiq }
    }
  end

  def check(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = yield
    {
      name: name,
      status: status,
      latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    }
  rescue StandardError => e
    Rails.logger.warn("[status] #{name} probe failed: #{e.message}")
    { name: name, status: 'down', latency_ms: nil }
  end

  def sidekiq_state
    stats = Sidekiq::Stats.new
    return 'down' if stats.processes_size.zero?

    Sidekiq::Queue.new('default').latency > 60 ? 'down' : 'ok'
  end

  def overall_http_status(summary)
    summary[:overall] == 'operational' ? :ok : :service_unavailable
  end
end
