# Test sandbox for an Athenas assistant: the operator talks to their own agent
# as if they were a customer, and sees what it answers before a real customer
# does. Administrators only, and always scoped to the current account.
class Api::V1::Accounts::Ai::PlaygroundController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant

  def show
    render json: { transcript: service.transcript }
  end

  def create
    message = params[:message].to_s.strip
    return render_could_not_create_error('Message is required') if message.blank?

    render json: service.send_message(message)
  rescue Ai::ClaudeService::Error => e
    render json: { status: 'error', error: e.message }, status: :unprocessable_entity
  end

  def destroy
    service.reset!
    head :no_content
  end

  private

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
