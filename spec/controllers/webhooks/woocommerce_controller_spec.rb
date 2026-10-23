require 'rails_helper'

RSpec.describe 'WooCommerce webhooks', type: :request do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:connection) do
    StoreConnection.create!(account: account, store_url: 'https://loja.lizzon.com.br', consumer_key: 'ck_x', consumer_secret: 'cs_x')
  end
  let(:body) { Rails.root.join('spec/fixtures/files/woocommerce/order.json').read }

  def deliver(token: connection.webhook_token, signature: Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', connection.webhook_secret, body)),
              raw: body, content_type: 'application/json')
    post "/webhooks/woocommerce/#{token}", params: raw,
                                           headers: { 'CONTENT_TYPE' => content_type, 'X-WC-Webhook-Signature' => signature }.compact
  end

  it 'queues a signed order for import' do
    expect { deliver }.to have_enqueued_job(Woocommerce::WebhookJob).with(connection.id, body)
    expect(response).to have_http_status(:ok)
  end

  it 'refuses a body signed with another secret' do
    expect { deliver(signature: 'forged') }.not_to have_enqueued_job(Woocommerce::WebhookJob)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers the ping WooCommerce sends when the webhook is created' do
    deliver(signature: nil, raw: 'webhook_id=12', content_type: 'application/x-www-form-urlencoded')

    expect(response).to have_http_status(:ok)
  end

  it 'does not know an unknown token' do
    deliver(token: 'nope')

    expect(response).to have_http_status(:not_found)
  end

  it 'imports the order the job receives' do
    Woocommerce::WebhookJob.perform_now(connection.id, body)

    expect(connection.store_orders.pluck(:number)).to eq(['1042'])
  end
end
