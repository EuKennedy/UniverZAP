require 'rails_helper'

RSpec.describe 'WooCommerce integration API', type: :request do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/integrations/woocommerce" }
  let(:connection) do
    StoreConnection.create!(account: account, store_url: 'https://loja.lizzon.com.br', consumer_key: 'ck_x', consumer_secret: 'cs_secret')
  end

  it 'does not exist for a workspace that is not e-commerce' do
    account.update!(custom_attributes: { 'vertical_template' => 'beauty_salon' })

    get base, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'shows the connection without ever returning the keys', :aggregate_failures do
    connection

    get base, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('connected' => true, 'store_url' => 'https://loja.lizzon.com.br', 'orders_count' => 0)
    expect(response.body).not_to include('cs_secret')
  end

  it 'reports the connector error back to the admin' do
    allow(Woocommerce::ConnectService).to receive(:new).and_return(instance_double(Woocommerce::ConnectService))
    allow(Woocommerce::ConnectService.new(account)).to receive(:connect).and_raise(Woocommerce::Client::Error, 'WooCommerce respondeu 401')

    post base, params: { store_url: 'https://loja.x', consumer_key: 'ck', consumer_secret: 'cs' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('WooCommerce respondeu 401')
  end

  it 'does not let an agent connect a store' do
    post base, params: { store_url: 'https://loja.x', consumer_key: 'ck', consumer_secret: 'cs' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'gives any agent the contact orders and spend for the sheet', :aggregate_failures do
    contact = create(:contact, account: account)
    { '1' => ['processing', 100], '2' => ['completed', 50], '3' => ['pending', 999] }.each do |id, (status, total)|
      connection.store_orders.create!(account: account, contact: contact, external_id: id, number: id, status: status,
                                      total: total, placed_at: id.to_i.days.ago)
    end

    get "#{base}/orders", params: { contact_id: contact.id }, headers: agent.create_new_auth_token

    body = response.parsed_body
    expect(body['metrics']).to include('orders_count' => 2, 'total_spent' => 150.0, 'average_ticket' => 75.0)
    expect(body['orders'].pluck('number')).to eq(%w[1 2 3])
    expect(body['orders'].first['admin_url']).to eq('https://loja.lizzon.com.br/wp-admin/post.php?post=1&action=edit')
  end
end
