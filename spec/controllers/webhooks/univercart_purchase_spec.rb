# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::UnivercartController#create — purchase.completed', type: :request do
  let(:secret) { 'test-univercart-secret' }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:subscription) do
    UnivercartSubscription.create!(
      external_user_id: 'buyer-abc123',
      email: user.email,
      name: 'Buyer',
      role: 'admin',
      status: 'active',
      user: user
    )
  end

  before { subscription } # materialize for the webhook resolver

  around do |example|
    original = ENV.fetch('UNIVERCART_WEBHOOK_SECRET', nil)
    ENV['UNIVERCART_WEBHOOK_SECRET'] = secret
    example.run
    ENV['UNIVERCART_WEBHOOK_SECRET'] = original
  end

  # Univercart::Signature expects `t=<ts>,v1=<hex>` where hex is the
  # HMAC-SHA256 of `"<ts>.<raw_body>"` — NOT a `sha256=<hex>` prefix
  # like Stripe. Mirror that contract here so the verifier accepts
  # the test events.
  def sign(body)
    ts = Time.current.to_i
    digest = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{body}")
    "t=#{ts},v1=#{digest}"
  end

  def post_event(payload)
    body = payload.to_json
    post '/univercart-webhook', params: body, headers: {
      'Content-Type' => 'application/json',
      'X-Univercart-Signature' => sign(body)
    }
  end

  it 'credits the bonus-aware amount for the R$100 pack and is idempotent on retry' do
    payload = {
      id: 'evt_p1',
      type: 'purchase.completed',
      data: {
        externalUserId: 'buyer-abc123',
        productSlug: 'athenas-tokens-100',
        amountCents: 10_000,
        currency: 'BRL',
        transactionId: 'tx_100'
      }
    }

    expect { post_event(payload) }.to change {
      account.reload.token_credit_lifetime_purchased_cents_brl
    }.by(11_000) # R$100 pago → R$110 creditado (bônus +10%)

    expect(response).to have_http_status(:ok)

    # Univercart retries the same event id → second call must be a no-op.
    payload[:id] = 'evt_p1_retry'
    expect { post_event(payload) }.not_to(change do
      account.reload.token_credit_lifetime_purchased_cents_brl
    end)
  end

  it 'falls back to amountCents when the productSlug is unknown' do
    payload = {
      id: 'evt_p2',
      type: 'purchase.completed',
      data: {
        externalUserId: 'buyer-abc123',
        productSlug: 'unknown-promo',
        amountCents: 7_500,
        currency: 'BRL',
        transactionId: 'tx_promo'
      }
    }

    expect { post_event(payload) }.to change {
      account.reload.token_credit_lifetime_purchased_cents_brl
    }.by(7_500)
  end

  it 'logs and skips when the subscription cannot be resolved' do
    payload = {
      id: 'evt_p3',
      type: 'purchase.completed',
      data: {
        externalUserId: 'unknown-buyer',
        productSlug: 'athenas-tokens-50',
        amountCents: 5_000,
        currency: 'BRL',
        transactionId: 'tx_50'
      }
    }

    expect { post_event(payload) }.not_to change(Ai::CreditLedgerEntry, :count)
    expect(response).to have_http_status(:ok)
  end
end
