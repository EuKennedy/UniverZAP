class Api::V1::Accounts::OnboardingStateController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/onboarding_state
  # Aggregated readiness signals for the onboarding launcher + tour.
  # Cached 30s per account to keep the floating widget cheap on dashboard mount.
  #
  # PATCH /api/v1/accounts/:account_id/onboarding_state
  # Persists onboarding `custom_attributes` keys (tour progress, completed
  # contextual tours, dismissal flags). Returns the same payload as `show`.
  def show
    state = Rails.cache.fetch(cache_key, expires_in: 30.seconds) { build_state }
    render json: state.merge(custom_attributes: onboarding_attrs)
  end

  def update
    persist_custom_attributes!(patch_params)
    invalidate_cache!
    state = build_state
    render json: state.merge(custom_attributes: onboarding_attrs)
  end

  private

  def cache_key
    "onboarding_state:account_#{Current.account.id}:v5"
  end

  def invalidate_cache!
    Rails.cache.delete(cache_key)
  end

  # The launcher hides as soon as the tenant looks configured. Having even
  # a single inbox connected is enough — accounts already running in
  # production should never see the FAB again. Brand new tenants with zero
  # inboxes are the only ones we keep nudging.
  def build_state
    flags = readiness_flags
    flags.merge(
      completed: completed?(flags),
      regressed_steps: regressed_steps(flags)
    )
  end

  def completed?(flags)
    flags[:has_inbox]
  end

  # Compare current readiness against the snapshot we cached when the user
  # last finished the main tour. Anything previously green that flipped back
  # to red counts as a regression — the launcher uses this to reappear with
  # a targeted nudge ("Finish what you undid").
  def regressed_steps(flags)
    snapshot = (Current.account.custom_attributes || {})['onboarding_readiness_snapshot'] || {}
    flags.each_with_object([]) do |(key, present), acc|
      acc << key.to_s if !present && snapshot[key.to_s]
    end
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
      'onboarding_completed_tours',
      'onboarding_tour_completed_at',
      'onboarding_explicit_dismiss',
      'onboarding_last_step_index',
      'onboarding_readiness_snapshot'
    )
  end

  # Whitelist of keys the client is allowed to write. Anything else gets
  # ignored so a curious operator can't poison the account custom_attrs
  # via this endpoint.
  PATCH_KEYS = %w[
    onboarding_completed_steps
    onboarding_completed_tours
    onboarding_tour_completed_at
    onboarding_explicit_dismiss
    onboarding_last_step_index
    onboarding_readiness_snapshot
  ].freeze

  # Strong params can't express nested mixed shapes (string + array + hash),
  # so we lift to a raw hash and hard-slice against the whitelist. The
  # PATCH_KEYS constant is hardcoded — nothing the client sends can sneak
  # past it. Booleans / ISO strings / arrays of strings / nested hashes
  # all pass through untouched.
  def patch_params
    nested = params[:custom_attributes]
    return {} if nested.blank?

    raw = nested.respond_to?(:to_unsafe_h) ? nested.to_unsafe_h : nested.to_h
    raw.deep_stringify_keys.slice(*PATCH_KEYS)
  end

  def persist_custom_attributes!(patch)
    return if patch.blank?

    base = Current.account.custom_attributes || {}
    Current.account.update!(custom_attributes: base.merge(patch))
  end
end
