require 'rails_helper'

RSpec.describe Ai::Calendar::GoogleClient do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:connection) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt-1'
    )
  end
  let(:client) { described_class.new(connection) }
  let(:token_url) { 'https://oauth2.googleapis.com/token' }
  let(:freebusy_url) { 'https://www.googleapis.com/calendar/v3/freeBusy' }
  let(:events_url) { 'https://www.googleapis.com/calendar/v3/calendars/primary/events' }

  def stub_token(body = { access_token: 'at-1' }, status = 200)
    stub_request(:post, token_url).to_return(status: status, body: body.to_json,
                                             headers: { 'content-type' => 'application/json' })
  end

  describe '#busy' do
    it 'returns the periods Google says are taken' do
      stub_token
      stub_request(:post, freebusy_url).to_return(
        status: 200,
        body: { calendars: { primary: { busy: [{ start: '2026-09-02T12:00:00Z', end: '2026-09-02T13:00:00Z' }] } } }.to_json
      )

      periods = client.busy(calendar_id: 'primary', from: Time.zone.parse('2026-09-02'), to: Time.zone.parse('2026-09-03'))

      expect(periods.size).to eq(1)
      expect(periods.first.begin).to eq(Time.zone.parse('2026-09-02T12:00:00Z'))
    end

    it 'reads an empty calendar as free rather than failing' do
      stub_token
      stub_request(:post, freebusy_url).to_return(status: 200, body: { calendars: { primary: {} } }.to_json)

      expect(client.busy(calendar_id: 'primary', from: Time.current, to: 1.day.from_now)).to eq([])
    end
  end

  # The operator removed our access. The agent has to stop promising times, and
  # the screen has to be able to say why, so this is recorded rather than
  # retried forever.
  describe 'a grant Google no longer honours' do
    it 'revokes the connection when the refresh token is rejected' do
      stub_token({ error: 'invalid_grant', error_description: 'Token has been expired or revoked.' }, 400)

      expect { client.busy(calendar_id: 'primary', from: Time.current, to: 1.day.from_now) }
        .to raise_error(described_class::Revoked)
      expect(connection.reload.status).to eq('revoked')
      expect(connection.last_error).to include('revoked')
    end

    it 'revokes the connection when the calendar call answers 401' do
      stub_token
      stub_request(:post, freebusy_url).to_return(status: 401, body: '{}')

      expect { client.busy(calendar_id: 'primary', from: Time.current, to: 1.day.from_now) }
        .to raise_error(described_class::Revoked)
      expect(connection.reload).to be_revoked
    end
  end

  describe '#create_event' do
    it 'returns the created event so the caller can keep its id' do
      stub_token
      stub_request(:post, events_url).to_return(status: 200, body: { id: 'evt-1' }.to_json)

      expect(client.create_event(calendar_id: 'primary', payload: { summary: 'Progressiva' })['id']).to eq('evt-1')
    end

    it 'raises a plain error on a refusal that is not about the grant' do
      stub_token
      stub_request(:post, events_url).to_return(status: 400, body: 'bad request')

      expect { client.create_event(calendar_id: 'primary', payload: {}) }.to raise_error(described_class::Error)
      expect(connection.reload.status).to eq('active')
    end
  end

  # An event that is already gone is the outcome the caller wanted.
  describe '#delete_event' do
    it 'treats 410 as success' do
      stub_token
      stub_request(:delete, "#{events_url}/evt-1").to_return(status: 410, body: '')

      expect(client.delete_event(calendar_id: 'primary', event_id: 'evt-1')).to be(true)
    end

    it 'succeeds on a normal 204' do
      stub_token
      stub_request(:delete, "#{events_url}/evt-1").to_return(status: 204, body: '')

      expect(client.delete_event(calendar_id: 'primary', event_id: 'evt-1')).to be(true)
    end
  end
end
