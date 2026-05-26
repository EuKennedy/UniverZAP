class Lgpd::UserExportService
  def initialize(user)
    @user = user
  end

  def call
    {
      generated_at: Time.current.iso8601,
      product: 'UniverZAP',
      lgpd_article: 'Art. 18 V (portabilidade)',
      profile: profile_payload,
      acceptance: acceptance_payload,
      accounts: accounts_payload,
      sessions: sessions_payload,
      audits: audits_payload
    }
  end

  private

  def profile_payload
    {
      id: @user.id,
      name: @user.name,
      email: @user.email,
      display_name: @user.display_name,
      provider: @user.provider,
      uid: @user.uid,
      custom_attributes: @user.custom_attributes,
      message_signature: @user.message_signature,
      ui_settings: @user.ui_settings,
      created_at: @user.created_at,
      last_sign_in_at: @user.last_sign_in_at
    }
  end

  def acceptance_payload
    {
      accepted_terms_version: @user.accepted_terms_version,
      accepted_privacy_version: @user.accepted_privacy_version,
      accepted_at: @user.accepted_at
    }
  end

  def accounts_payload
    @user.account_users.includes(:account).map do |membership|
      {
        account_id: membership.account_id,
        account_name: membership.account.name,
        role: membership.role,
        custom_role_id: membership.custom_role_id,
        availability: membership.availability,
        joined_at: membership.created_at
      }
    end
  end

  def sessions_payload
    @user.access_token ? [{ token_id: @user.access_token.id, created_at: @user.access_token.created_at }] : []
  end

  def audits_payload
    return [] unless defined?(Audited::Audit)

    Audited::Audit.where(user: @user).limit(500).map do |audit|
      {
        action: audit.action,
        auditable_type: audit.auditable_type,
        auditable_id: audit.auditable_id,
        audited_changes: audit.audited_changes,
        created_at: audit.created_at
      }
    end
  end
end
