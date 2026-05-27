class Api::V1::Accounts::Ai::AssistantsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin, only: %i[create update destroy duplicate]
  before_action :fetch_assistant, except: [:index, :create]

  def index
    # Eager-load counts so the jbuilder partial's `meta_payload` stats
    # (trainings/intents/invocations) don't fire N+3 queries per assistant
    # when the index returns dozens of rows.
    @assistants = Current.account.ai_assistants
                         .order(:name)
                         .left_joins(:trainings, :intents, :invocations)
                         .select(
                           'ai_assistants.*',
                           'COUNT(DISTINCT ai_trainings.id) AS trainings_count',
                           'COUNT(DISTINCT ai_intents.id) AS intents_count',
                           'COUNT(DISTINCT ai_invocations.id) AS invocations_count'
                         )
                         .group('ai_assistants.id')
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
    # Never copy the encrypted provider credentials into the clone — they're
    # silently carried over with the rest of the attributes hash otherwise,
    # and an operator who only meant to clone the persona walks away with a
    # second assistant holding the original API key. Reset to blank; the
    # admin must paste the key again on edit.
    new_attrs = @assistant.attributes.except(
      'id', 'created_at', 'updated_at',
      'encrypted_anthropic_key', 'encrypted_openai_key'
    )
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
