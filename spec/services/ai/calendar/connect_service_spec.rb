require 'rails_helper'

RSpec.describe Ai::Calendar::ConnectService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:profile) { { 'email' => 'salao@gmail.com', 'name' => 'Salão Lizzon' } }
  let(:token) { instance_double(OAuth2::AccessToken, refresh_token: 'rt-1') }

  before do
    allow(token).to receive(:get).and_return(instance_double(OAuth2::Response, parsed: profile))
  end

  def connect(with = token)
    described_class.new(assistant: assistant, token: with).perform
  end

  it 'stores the grant against the agent, never the account' do
    connection = connect

    expect(connection.ai_assistant_id).to eq(assistant.id)
    expect(connection.google_email).to eq('salao@gmail.com')
    expect(connection.status).to eq('active')
  end

  # Operators reconnect when they are not sure it worked. A second grant would
  # leave the agent guessing which one is live.
  it 'refreshes the same connection when the account is connected twice' do
    first = connect
    second = connect(instance_double(OAuth2::AccessToken, refresh_token: 'rt-2', get: instance_double(OAuth2::Response, parsed: profile)))

    expect(second.id).to eq(first.id)
    expect(second.encrypted_refresh_token).to eq('rt-2')
    expect(assistant.calendar_connections.count).to eq(1)
  end

  # Writing to the account's own calendar is what makes the owner's dentist
  # appointment block a slot without anybody copying it into our tables.
  it 'creates the one agenda the MVP shows, pointed at the primary calendar' do
    professional = connect.professionals.first

    expect(professional.calendar_id).to eq('primary')
    expect(professional.name).to eq('Salão Lizzon')
    expect(professional.ai_assistant_id).to eq(assistant.id)
  end

  it 'does not create a second agenda on reconnect' do
    connect
    connect

    expect(Ai::Calendar::Professional.where(ai_assistant_id: assistant.id).count).to eq(1)
  end

  # Two hours is the operator's number, not a guess: past it the agent stops
  # touching the appointment and a human decides.
  it 'creates the scheduling rules with the two-hour cancellation window' do
    connect

    setting = assistant.reload.calendar_setting
    expect(setting).to be_present
    expect(setting.cancellation_window_hours).to eq(2)
  end

  # The token is the valuable part. A nameless connection still works, so a
  # profile lookup that fails must not cost the operator the whole grant.
  it 'keeps the grant when Google will not say who authorised it' do
    allow(token).to receive(:get).and_raise(StandardError, 'boom')

    expect(connect.encrypted_refresh_token).to eq('rt-1')
  end
end
