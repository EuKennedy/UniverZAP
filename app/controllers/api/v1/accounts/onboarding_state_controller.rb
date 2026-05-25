class Api::V1::Accounts::OnboardingStateController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/onboarding_state
  # Aggregated readiness signals for the onboarding launcher + tour.
  # Cached 30s per account to keep the floating widget cheap on dashboard mount.
  def show
    state = Rails.cache.fetch(cache_key, expires_in: 30.seconds) { build_state }
    render json: state.merge(custom_attributes: onboarding_attrs)
  end

  private

  def cache_key
    "onboarding_state:account_#{Current.account.id}:v2"
  end

  def build_state
    flags = readiness_flags
    flags.merge(completed: flags.values.all?)
  end

  def readiness_flags
    account = Current.account
    {
      has_inbox: account.inboxes.exists?,
      has_team_members: account.account_users.count > 1,
      has_team_group: account.teams.exists?,
      has_assistant: assistant_with_prompt?(account),
      has_first_reply: account.messages.outgoing.where(sender_type: 'User').exists?
    }
  end

  def assistant_with_prompt?(account)
    account.ai_assistants
           .where.not(system_prompt: [nil, ''])
           .where.not('system_prompt LIKE ?', '%Assistente padrão criado automaticamente%')
           .exists?
  end

  def onboarding_attrs
    (Current.account.custom_attributes || {}).slice(
      'onboarding_completed_steps',
      'onboarding_tour_completed_at',
      'onboarding_explicit_dismiss',
      'onboarding_last_step_index'
    )
  end
end
