class Api::V1::Accounts::Ai::AssistantsController < Api::V1::Accounts::BaseController
  # analytics exposes spend, so it is admin-only like the write actions.
  # `themes` returns raw customer text from the response log, so it belongs with
  # the write actions and the spend report, not with the read-only list.
  before_action :ensure_admin, only: %i[create update destroy duplicate analytics themes]
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

  # Real performance numbers for this agent, measured from the invocation log.
  def analytics
    render json: Ai::AnalyticsService.new(assistant: @assistant, days: params[:days] || 30).perform
  end

  # What customers keep asking. Free to compute: the questions are already in
  # the response log, and the operator needs the word their customers use, not
  # a label a model invented for them.
  def themes
    render json: Ai::ThemeService.new(assistant: @assistant, days: params[:days] || 30).perform
  end

  def create
    @assistant = Current.account.ai_assistants.new(permitted_params)
    apply_template if params[:template].present?
    @assistant.save!
    seed_template_knowledge
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

  # A template fills only what the operator left blank, so someone who typed a
  # name and then picked a vertical does not lose what they typed.
  def apply_template
    template = Ai::AgentTemplates.find(params[:template])
    return if template.blank?

    @template = template
    @assistant.role = template[:role] if @assistant.role.blank?
    @assistant.description = template[:description] if @assistant.description.blank?
    @assistant.tone = template[:tone] if @assistant.tone.blank?
    @assistant.system_prompt = template[:system_prompt] if @assistant.system_prompt.blank?
  end

  # The starter documents are the point: an agent with instructions and an empty
  # knowledge base has nothing it is allowed to assert, so it deflects every
  # question and the operator concludes the AI does not work.
  def seed_template_knowledge
    return if @template.blank?

    @template[:trainings].each do |doc|
      @assistant.trainings.create!(
        account: Current.account, title: doc[:title], category: doc[:category],
        source_type: 'text', content: doc[:content], status: 'ready'
      )
    end
  end

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
      guardrails: {},
      behavior_flags: [:split_messages, :reply_marking, :voice_replies]
    )
  end
end
