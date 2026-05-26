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
    "onboarding_state:account_#{Current.account.id}:v4"
  end

  # The launcher hides as soon as the tenant looks configured. Having even
  # a single inbox connected is enough — accounts already running in
  # production should never see the FAB again. Brand new tenants with zero
  # inboxes are the only ones we keep nudging.
  def build_state
    flags = readiness_flags
    flags.merge(completed: completed?(flags))
  end

  def completed?(flags)
    flags[:has_inbox]
  end

  def readiness_flags
    {
      has_inbox: inbox_present?,
      has_team_members: team_members_present?,
      has_team_group: team_group_present?,
      has_assistant: assistant_present?,
      has_first_reply: first_reply_present?
    }
  end

  def inbox_present?
    Current.account.inboxes.exists?
  end

  def team_members_present?
    Current.account.account_users.count > 1
  end

  def team_group_present?
    Current.account.teams.exists?
  end

  def assistant_present?
    Current.account.ai_assistants.where.not(system_prompt: [nil, '']).exists?
  end

  def first_reply_present?
    Current.account.messages.outgoing.exists?(sender_type: 'User')
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
