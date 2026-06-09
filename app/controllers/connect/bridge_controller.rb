class Connect::BridgeController < ApplicationController
  # ApplicationController do Chatwoot exige auth — pulamos (usuário ainda não logou).
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :check_account_blocked, raise: false
  skip_before_action :ensure_user_belongs_to_account, raise: false
  skip_before_action :check_univercart_status, raise: false
  layout false

  BRIDGE_SECRET = -> { ENV.fetch('UNIVERZAP_BRIDGE_SECRET') }

  # GET /connect/bridge?t=<JWT belezaki>
  def show
    token = params[:t]
    return render plain: 'Token ausente.', status: :bad_request if token.blank?

    result = Belezaki::BridgeJwt.verify(jwt: token, secret: BRIDGE_SECRET.call)
    return render plain: "Link inválido (#{result.reason}).", status: :unauthorized unless result.ok

    claims = result.claims
    return render plain: 'Link já utilizado.', status: :gone unless consume_jti!(claims['jti'], claims['exp'])

    user = provision_user!(claims)
    upsert_subscription!(user, claims)

    # SSO login automático — mesmo helper usado em todo o app (FRONTEND_URL/app/login).
    redirect_to user.generate_sso_link, allow_other_host: true
  end

  private

  # Single-use: SET NX EX atômico. Retorna false se o jti já existia (replay).
  def consume_jti!(jti, exp)
    ttl = [exp.to_i - Time.current.to_i, 60].max
    ::Redis::Alfred.set("belezaki_bridge_jti:#{jti}", true, nx: true, ex: ttl)
  end

  # Cria/atualiza User + Account + AccountUser admin. Idempotente por e-mail.
  # Espelha SetupController#provision_user!, mas com senha aleatória (entrada via SSO).
  def provision_user!(claims)
    ActiveRecord::Base.transaction do
      user = upsert_user(claims)
      ensure_user_has_account(user, claims['accountName'])
      user
    end
  end

  def upsert_user(claims)
    user = User.find_or_initialize_by(email: claims['email'].to_s.strip.downcase)
    if user.new_record?
      create_bridge_user(user, claims)
    else
      user.update!(custom_attributes: (user.custom_attributes || {}).merge(bridge_user_attrs(claims).stringify_keys))
    end
    user
  end

  def create_bridge_user(user, claims)
    pwd = SecureRandom.base58(24)
    user.assign_attributes(
      name: claims['name'].presence || 'Titular',
      password: pwd,
      password_confirmation: pwd,
      confirmed_at: Time.current,
      custom_attributes: bridge_user_attrs(claims),
      ui_settings: { locale: 'pt_BR' }
    )
    user.save!
  end

  def bridge_user_attrs(claims)
    { belezaki_external_user_id: claims['sub'], univercart_role: claims['role'] }
  end

  def ensure_user_has_account(user, account_name)
    return unless user.accounts.empty?

    account = Account.create!(name: account_name.presence || 'Meu negócio', locale: 'pt_BR')
    AccountUser.create!(user: user, account: account, role: :administrator)
  end

  # Mantém o guard de cobrança feliz (status active). Keyed pelo mesmo
  # external_user_id do Univercart, então o webhook de suspend/revoke atualiza
  # a mesma linha. email/name são NOT NULL no schema — preenchemos do JWT.
  def upsert_subscription!(user, claims)
    sub = UnivercartSubscription.find_or_initialize_by(external_user_id: claims['sub'])
    sub.id ||= SecureRandom.uuid
    sub.assign_attributes(
      user_id: user.id,
      email: claims['email'].to_s.strip.downcase,
      name: claims['name'].presence || 'Titular',
      role: claims['role'],
      status: 'active'
    )
    sub.save!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[bridge] subscription upsert falhou: #{e.message}")
  end
end
