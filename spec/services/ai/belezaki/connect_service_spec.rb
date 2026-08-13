require 'rails_helper'

RSpec.describe Ai::Belezaki::ConnectService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:service) { described_class.new(assistant: assistant) }
  let(:salon_url) { 'https://api.belezaki.com.br/api/agent/v1/salon' }

  before do
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).with(account).and_return('ext-1')
    allow(Ai::Belezaki::AgentClient).to receive(:api_key).and_return('shared-key')
  end

  def stub_salon(status, body)
    stub_request(:get, salon_url)
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'stores the salon the probe answered with' do
    stub_salon(200, { 'name' => 'Studio Bella', 'timezone' => 'America/Sao_Paulo' })

    connection = service.perform

    expect(connection.salon_name).to eq('Studio Bella')
    expect(connection.external_id).to eq('ext-1')
    expect(connection).to be_active
  end

  # The salon says which timezone it runs in; assuming ours would offer times in
  # the wrong hour to every salon outside São Paulo.
  it 'keeps the timezone the salon reported' do
    stub_salon(200, { 'name' => 'Bella', 'timezone' => 'America/Manaus' })

    expect(service.perform.timezone).to eq('America/Manaus')
  end

  # An account that never went through the belezaki login bridge has no salon to
  # bind to. That is onboarding, not a fault, and the message has to say so.
  it 'refuses when the account is not linked to a salon' do
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return(nil)

    expect { service.perform }.to raise_error(described_class::NotLinked)
  end

  # The shared key lives on our server. Without it every belezaki route answers
  # 503, so telling the operator to try again would be a lie.
  it 'refuses when the shared key is not configured' do
    allow(Ai::Belezaki::AgentClient).to receive(:api_key).and_return(nil)

    expect { service.perform }.to raise_error(described_class::NotConfigured)
  end

  it 'refuses while a Google calendar holds this agent agenda' do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account,
      google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )

    expect { service.perform }.to raise_error(described_class::AgendaTaken)
  end

  # A failed probe must leave nothing behind: a row written here would show
  # "connected" for a salon the agent cannot actually reach.
  it 'writes no row when the probe fails' do
    stub_salon(404, { 'message' => 'Salão não encontrado para esta conta.' })

    expect { service.perform }.to raise_error(Ai::Belezaki::AgentClient::Error)
    expect(Ai::Belezaki::Connection.count).to eq(0)
  end

  # Reconnecting is one click for the operator, so it must not collide with the
  # one-connection-per-agent rule.
  it 'reconnects onto the same row instead of failing on uniqueness' do
    stub_salon(200, { 'name' => 'Bella' })
    service.perform
    assistant.belezaki_connection.revoke!('token rejected')

    connection = described_class.new(assistant: assistant.reload).perform

    expect(connection).to be_active
    expect(connection.last_error).to be_nil
    expect(Ai::Belezaki::Connection.count).to eq(1)
  end
end
