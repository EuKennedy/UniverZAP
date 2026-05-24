class Connect::SetupController < ApplicationController
  # ApplicationController do Chatwoot exige auth — pulamos aqui.
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :check_account_blocked, raise: false
  skip_before_action :ensure_user_belongs_to_account, raise: false
  skip_before_action :check_univercart_status, raise: false
  layout false # sem chrome do app

  PARTNER_SLUG = -> { ENV.fetch('UNIVERCART_PARTNER_SLUG', 'univerzap') }
  JWT_SECRET   = -> { ENV.fetch('UNIVERCART_JWT_SECRET') }

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
    token    = params[:token]
    password = params[:password].to_s

    if password.length < 8
      return render plain: 'Senha muito curta (mínimo 8 caracteres).', status: :bad_request
    end

    result = Univercart::Jwt.verify(
      jwt: token,
      jwt_secret: JWT_SECRET.call,
      expected_audience: PARTNER_SLUG.call
    )
    return render plain: 'Sessão expirada. Recomece pelo email.', status: :unauthorized unless result.ok

    claims = result.claims
    sub = UnivercartSubscription.find_by(external_user_id: claims['sub'])
    return render plain: 'Assinatura não localizada. Aguarde o processamento.', status: :not_found unless sub

    user = provision_user!(claims, password)
    sub.update!(user_id: user.id)

    sign_in(user, scope: :user)
    redirect_to "/app/accounts/#{user.accounts.first.id}/dashboard"
  end

  private

  # Cria User + Account + AccountUser (administrator). Ultra = 1 account isolado por buyer.
  def provision_user!(claims, password)
    ActiveRecord::Base.transaction do
      user = User.find_or_initialize_by(email: claims['email'])
      if user.new_record?
        user.assign_attributes(
          name: claims['name'],
          password: password,
          password_confirmation: password,
          confirmed_at: Time.current,
          custom_attributes: {
            univercart_subscription_id: claims['sub'],
            univercart_role: claims['role']
          }
        )
        user.save!
      else
        user.update!(
          password: password,
          password_confirmation: password,
          custom_attributes: (user.custom_attributes || {}).merge(
            'univercart_subscription_id' => claims['sub'],
            'univercart_role'            => claims['role']
          )
        )
      end

      if user.accounts.empty?
        account = Account.create!(name: claims['name'])
        AccountUser.create!(user: user, account: account, role: :administrator)
      end

      user
    end
  end
end
