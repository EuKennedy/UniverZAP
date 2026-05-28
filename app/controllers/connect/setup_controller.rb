class Connect::SetupController < ApplicationController
  # ApplicationController do Chatwoot exige auth — pulamos aqui.
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :check_account_blocked, raise: false
  skip_before_action :ensure_user_belongs_to_account, raise: false
  skip_before_action :check_univercart_status, raise: false
  layout false # sem chrome do app

  PARTNER_SLUG = -> { ENV.fetch('UNIVERCART_PARTNER_SLUG', 'univerzap') }
  JWT_SECRET   = -> { ENV.fetch('UNIVERCART_JWT_SECRET') }

  PASSWORD_RULES = {
    length: ->(v) { v.length >= 8 },
    upper: ->(v) { v =~ /[A-Z]/ },
    lower: ->(v) { v =~ /[a-z]/ },
    special: ->(v) { v =~ %r{[ !@#$%^&*()_+\-=\[\]{}|"/\\.,`<>:;?~']} }
  }.freeze

  # GET /connect/setup?t=<JWT>
  def show
    token = params[:t]
    return render plain: 'Token ausente.', status: :bad_request if token.blank?

    result = Univercart::Jwt.verify(
      jwt: token,
      jwt_secret: JWT_SECRET.call,
      expected_audience: PARTNER_SLUG.call
    )
    unless result.ok
      return render plain: "Link inválido ou expirado (#{result.reason}). Solicite um novo.",
                    status: :unauthorized
    end

    # Redeem ANTES do form — garante single-use.
    unless Univercart::Redeem.consume(jti: result.claims['jti'])
      return render plain: 'Este link já foi usado ou expirou. Solicite um novo.',
                    status: :gone
    end

    @claims = result.claims
    @token  = token
  end

  # POST /connect/setup
  def create
    return unless verify_setup_token

    inputs = setup_params
    error = validate_setup_input(inputs[:company_name], inputs[:password], inputs[:password_confirmation])
    return render_setup_error(error) if error

    sub = find_subscription
    return unless sub

    complete_setup(sub, inputs)
  end

  private

  def verify_setup_token
    @token = params[:token]
    result = Univercart::Jwt.verify(
      jwt: @token,
      jwt_secret: JWT_SECRET.call,
      expected_audience: PARTNER_SLUG.call
    )
    return @claims = result.claims if result.ok

    render plain: 'Sessão expirada. Recomece pelo email.', status: :unauthorized
    false
  end

  def setup_params
    {
      company_name: params[:company_name].to_s.strip,
      password: params[:password].to_s,
      password_confirmation: params[:password_confirmation].to_s
    }
  end

  def find_subscription
    sub = UnivercartSubscription.find_by(external_user_id: @claims['sub'])
    return sub if sub

    render plain: 'Assinatura não localizada. Aguarde o processamento.', status: :not_found
    nil
  end

  def complete_setup(sub, inputs)
    user = provision_user!(@claims, inputs[:password], inputs[:company_name])
    sub.update!(user_id: user.id)
    sign_in(user, scope: :user)
    redirect_to "/app/accounts/#{user.accounts.first.id}/dashboard"
  end

  def validate_setup_input(company_name, password, password_confirmation)
    return 'Informe o nome da empresa (mínimo 2 caracteres).' if company_name.length < 2
    return 'As senhas não conferem.' if password != password_confirmation

    missing = PASSWORD_RULES.reject { |_, rule| rule.call(password) }.keys
    return password_rules_message(missing) if missing.any?

    nil
  end

  def password_rules_message(missing)
    labels = {
      length: '8+ caracteres',
      upper: '1 letra maiúscula',
      lower: '1 letra minúscula',
      special: '1 caractere especial'
    }
    "Senha não atende: #{missing.map { |k| labels[k] }.join(', ')}."
  end

  def render_setup_error(message)
    @setup_error = message
    render :show, status: :unprocessable_entity
  end

  # Cria User + Account + AccountUser (administrator). Ultra = 1 account isolado por buyer.
  def provision_user!(claims, password, company_name)
    ActiveRecord::Base.transaction do
      user = upsert_user(claims, password)
      ensure_user_has_account(user, company_name)
      user
    end
  end

  def upsert_user(claims, password)
    user = User.find_or_initialize_by(email: claims['email'])
    if user.new_record?
      create_new_user(user, claims, password)
    else
      update_existing_user(user, claims, password)
    end
    user
  end

  def create_new_user(user, claims, password)
    user.assign_attributes(
      name: claims['name'],
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current,
      custom_attributes: univercart_user_attrs(claims),
      # Brazilian customer base — every new self-service user should
      # land on a pt_BR dashboard. Operator can override later under
      # Profile → Preferences.
      ui_settings: { locale: 'pt_BR' }
    )
    user.save!
  end

  def update_existing_user(user, claims, password)
    user.update!(
      password: password,
      password_confirmation: password,
      custom_attributes: (user.custom_attributes || {}).merge(univercart_user_attrs(claims).stringify_keys)
    )
  end

  def univercart_user_attrs(claims)
    {
      univercart_subscription_id: claims['sub'],
      univercart_role: claims['role']
    }
  end

  def ensure_user_has_account(user, company_name)
    return unless user.accounts.empty?

    # Every Univercart-provisioned account is Brazilian by default. The
    # `locale: 'pt_BR'` ties into Account's enum so SwitchLocale + all
    # outgoing emails/notifications render in Portuguese without the
    # operator having to dig into Settings → General.
    account = Account.create!(name: company_name, locale: 'pt_BR')
    AccountUser.create!(user: user, account: account, role: :administrator)
  end
end
