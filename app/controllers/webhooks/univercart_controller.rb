# Webhook handler for Univercart Connect subscription lifecycle events.
# IMPORTANT: NÃO herda de ApplicationController — Chatwoot tem before_actions
# de auth que quebrariam o webhook. ActionController::API pula CSRF + cookies
# + session, exato o que queremos pra um endpoint server-to-server.
class Webhooks::UnivercartController < ActionController::API
  WEBHOOK_SECRET = -> { ENV.fetch('UNIVERCART_WEBHOOK_SECRET') }

  def create
    raw_body = request.raw_post
    return render_error('missing_signature', 400) if request.headers['X-Univercart-Signature'].blank?
    return render_error('invalid_signature', 401) unless signature_valid?(raw_body)

    event = JSON.parse(raw_body)
    return render json: { ok: true, duplicated: true } if UnivercartProcessedEvent.exists?(id: event['id'])

    dispatch_event(event)
    record_processed_event(event)
    render json: { ok: true }
  rescue JSON::ParserError
    render_error('invalid_payload', 400)
  rescue StandardError => e
    log_internal_error(e)
    render_error('internal', 500) # 5xx faz Univercart retentar
  end

  private

  def signature_valid?(raw_body)
    Univercart::Signature.verify(
      raw_body: raw_body,
      header: request.headers['X-Univercart-Signature'],
      secret: WEBHOOK_SECRET.call
    )
  end

  def record_processed_event(event)
    UnivercartProcessedEvent.create!(
      id: event['id'],
      event_type: event['type'],
      subscription_id: event.dig('data', 'externalUserId'),
      processed_at: Time.current
    )
  end

  def log_internal_error(error)
    Rails.logger.error(
      "[univercart.webhook] #{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
    )
  end

  def render_error(code, status)
    render json: { error: { code: code } }, status: status
  end

  def dispatch_event(event)
    data = event['data']
    case event['type']
    when 'entitlement.granted'      then handle_granted(data)
    when 'entitlement.role_changed' then handle_role_changed(data)
    when 'entitlement.suspended'    then handle_suspended(data)
    when 'entitlement.reactivated'  then handle_reactivated(data)
    when 'entitlement.revoked'      then handle_revoked(data)
    when 'purchase.completed'       then handle_purchase_completed(event, data)
    else
      Rails.logger.warn("[univercart.webhook] unknown type: #{event['type']}")
    end
  end

  # Univercart fires this once a one-off purchase (Athenas token pack)
  # settles. Payload shape:
  #   data: {
  #     externalUserId: "uuid",
  #     productSlug: "athenas-tokens-50" | "athenas-tokens-100" | "athenas-tokens-150",
  #     amountCents: 5000,            # what the buyer paid in BRL cents
  #     currency: "BRL",
  #     transactionId: "tx_abc123"    # idempotency key for the credit
  #   }
  # We map the slug → catalogue entry to recover the BONUS amount (R$100
  # pays in 10000 cents BRL but credits 11000 cents). External payment id
  # falls back to the event id so even a malformed payload stays idempotent
  # via the unique index on `ai_credit_ledger_entries.external_payment_id`.
  def handle_purchase_completed(event, data)
    return if data.blank?

    account = resolve_account(data['externalUserId'])
    return Rails.logger.warn("[univercart.webhook] purchase no_account ext=#{data['externalUserId']}") unless account

    package = ATHENAS_PACKAGES[data['productSlug']]
    credit_cents = package ? package[:credit_cents_brl] : data['amountCents'].to_i
    return Rails.logger.warn("[univercart.webhook] purchase zero_credit slug=#{data['productSlug']}") if credit_cents.zero?

    Ai::CreditLedger.new(account).credit_purchase!(
      cents_brl: credit_cents,
      external_payment_id: data['transactionId'].presence || event['id'],
      description: "Univercart purchase #{data['productSlug']}"
    )
  end

  # Mirror of the static catalogue on Api::V1::Accounts::Ai::CreditsController
  # — drives the bonus look-up. Kept tiny here on purpose so the webhook
  # doesn't reach into a controller; either side is fine to edit when we
  # tune the bonus tiers.
  ATHENAS_PACKAGES = {
    'athenas-tokens-50' => { credit_cents_brl: 5_000 },
    'athenas-tokens-100' => { credit_cents_brl: 11_000 },
    'athenas-tokens-150' => { credit_cents_brl: 18_000 }
  }.freeze

  # The buyer's Univercart `externalUserId` is the same value we already
  # store on UnivercartSubscription. From the subscription row we hop to
  # the User and their (single) Account. Returning the first account works
  # because the Univercart Connect flow provisions exactly one Account
  # per buyer.
  def resolve_account(external_user_id)
    return nil if external_user_id.blank?

    sub = UnivercartSubscription.find_by(external_user_id: external_user_id)
    sub&.user&.accounts&.first
  end

  def handle_granted(data)
    sub = UnivercartSubscription.find_or_initialize_by(external_user_id: data['externalUserId'])
    sub.assign_attributes(
      email: data['email'],
      name: data['name'],
      document: data['document'],
      phone: data['phone'],
      role: data['role'],
      status: 'active',
      product_slug: data['productSlug'],
      plan_id: data['planId'],
      billing_period: data['billingPeriod'],
      amount_cents: data['amountCents'],
      currency: data['currency'],
      valid_until: data['validUntil'],
      cancelled_at: nil,
      cancel_reason: nil
    )
    sub.save!
    # Univercart já enviou email + WhatsApp com magic link. Esperamos o
    # buyer clicar em /connect/setup.
  end

  def handle_role_changed(data)
    sub = UnivercartSubscription.find_by(external_user_id: data['externalUserId'])
    return unless sub

    sub.update!(role: data['role'], valid_until: data['validUntil'])
  end

  def handle_suspended(data)
    sub = UnivercartSubscription.find_by(external_user_id: data['externalUserId'])
    return unless sub

    sub.update!(status: 'suspended')
  end

  def handle_reactivated(data)
    sub = UnivercartSubscription.find_by(external_user_id: data['externalUserId'])
    return unless sub

    sub.update!(status: 'active', valid_until: data['validUntil'])
  end

  def handle_revoked(data)
    sub = UnivercartSubscription.find_by(external_user_id: data['externalUserId'])
    return unless sub

    sub.update!(
      status: 'cancelled',
      cancelled_at: data['revokedAt'],
      cancel_reason: data['reason']
    )
    # NÃO delete User/Account — LGPD + buyer pode reativar.
  end
end
