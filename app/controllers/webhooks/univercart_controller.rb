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
    else
      Rails.logger.warn("[univercart.webhook] unknown type: #{event['type']}")
    end
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
