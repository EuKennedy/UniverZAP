class Api::V1::Accounts::Ai::AssistantsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant, except: [:index, :create]

  def index
    @assistants = Current.account.ai_assistants.order(:name)
  end

  def show; end

  def create
    @assistant = Current.account.ai_assistants.new(permitted_params)
    @assistant.save!
    render :show
  end

  def update
    @assistant.update!(permitted_params)
    render :show
  end

  def destroy
    @assistant.destroy!
    head :ok
  end

  def duplicate
    new_attrs = @assistant.attributes.except('id', 'created_at', 'updated_at')
    new_attrs['name'] = "#{@assistant.name} (cópia)"
    @assistant = Current.account.ai_assistants.create!(new_attrs)
    render :show
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:id])
  end

  def permitted_params
    params.require(:ai_assistant).permit(
      :name, :role, :description, :avatar_url, :tone,
      :provider, :model, :system_prompt, :temperature, :max_tokens,
      :autopilot_enabled, :encrypted_anthropic_key, :encrypted_openai_key,
      :active,
      router_config: {},
      guardrails: {}
    )
  end
end
