require 'rails_helper'

RSpec.describe Ai::Calendar::GoogleCallbacksController do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:verifier) { Rails.application.message_verifier(:athenas_calendar_oauth) }
  let(:valid_state) { verifier.generate({ account_id: account.id, assistant_id: assistant.id }, expires_in: 15.minutes) }

  def stub_exchange(refresh_token:)
    token = instance_double(
      OAuth2::AccessToken, refresh_token: refresh_token,
                           get: instance_double(OAuth2::Response, parsed: { 'email' => 'salao@gmail.com', 'name' => 'Salão' })
    )
    auth_code = instance_double(OAuth2::Strategy::AuthCode, get_token: token)
    allow_any_instance_of(described_class).to receive(:google_calendar_client) # rubocop:disable RSpec/AnyInstance
      .and_return(instance_double(OAuth2::Client, auth_code: auth_code))
  end

  it 'connects the agent named in the signed state' do
    stub_exchange(refresh_token: 'rt-1')

    get :show, params: { code: 'abc', state: valid_state }

    expect(response).to redirect_to("/app/accounts/#{account.id}/athenas/#{assistant.id}?calendar=connected")
    expect(assistant.reload.calendar_connections.active.count).to eq(1)
  end

  # The callback runs outside the dashboard session, so the state is the only
  # thing proving which agent asked for this. A forged one must connect nothing.
  it 'refuses a state it did not sign' do
    stub_exchange(refresh_token: 'rt-1')

    get :show, params: { code: 'abc', state: 'not-a-real-state' }

    expect(response).to redirect_to('/?calendar=error&reason=invalid_state')
    expect(Ai::Calendar::Connection.count).to eq(0)
  end

  # An access token with no refresh token dies in an hour with no way to renew
  # it. Saving it would give the operator a connection that looks healthy today
  # and stops answering tomorrow morning.
  it 'refuses a grant that came back without a refresh token' do
    stub_exchange(refresh_token: nil)

    get :show, params: { code: 'abc', state: valid_state }

    expect(response).to redirect_to("/app/accounts/#{account.id}/athenas/#{assistant.id}?calendar=error&reason=no_refresh_token")
    expect(Ai::Calendar::Connection.count).to eq(0)
  end

  it 'refuses a state pointing at an agent from another account' do
    other = create(:ai_assistant, account: create(:account))
    stub_exchange(refresh_token: 'rt-1')

    get :show, params: { code: 'abc', state: verifier.generate({ account_id: account.id, assistant_id: other.id }) }

    expect(Ai::Calendar::Connection.count).to eq(0)
  end
end
