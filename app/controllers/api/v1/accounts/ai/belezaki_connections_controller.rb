# Binding ONE agent to a belezaki salon.
#
# Per agent, like the Google calendar next to it: the same operator may run a
# salon and a clinic as two agents, and one agenda must never answer for the
# other.
class Api::V1::Accounts::Ai::BelezakiConnectionsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :set_assistant

  def show
    render json: { connection: @assistant.belezaki_connection&.push_event_data }
  end

  # Each refusal gets its own code because the fixes are different people's
  # jobs: `not_linked` is the operator's onboarding, `not_configured` is ours,
  # and telling them apart is the difference between "do this" and "wait".
  def create
    render json: { connection: Ai::Belezaki::ConnectService.new(assistant: @assistant).perform.push_event_data }
  rescue Ai::Belezaki::ConnectService::NotLinked
    refuse('not_linked')
  rescue Ai::Belezaki::ConnectService::NotConfigured
    refuse('not_configured')
  rescue Ai::Belezaki::ConnectService::AgendaTaken
    refuse('agenda_taken')
  rescue Ai::Belezaki::AgentClient::Error => e
    Rails.logger.warn("[Belezaki] connect probe failed assistant=#{@assistant.id} code=#{e.code}: #{e.message}")
    refuse('probe_failed')
  end

  # Disconnecting only unbinds. Appointments already made stay in the salon's own
  # agenda: they are real customers at real times, and removing an integration is
  # not a reason to empty somebody's week.
  def destroy
    @assistant.belezaki_connection&.destroy
    head :ok
  end

  private

  # Connecting an agenda decides where every customer this agent talks to ends
  # up booked. Each Ai controller carries its own copy — there is no shared
  # helper for this in the base class.
  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  # Scoped to the current account's agents, so one workspace can never reach
  # another's agenda even with a guessed id.
  def set_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def refuse(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
