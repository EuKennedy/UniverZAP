require 'rails_helper'

RSpec.describe Belezaki::CustomerCardService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5531984956383') }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  let(:now) { Time.zone.parse('2026-10-19 12:00:00 -03:00') }
  let(:client_json) { { id: 'c1', name: 'Maria Souza', phone: '5531984956383' } }

  def appointment(id, status, start)
    { id: id, status: status, service: 'Escova', professional: 'Ana',
      start: start.iso8601, end: (start + 1.hour).iso8601, can_cancel: true, can_reschedule: true }
  end

  around do |example|
    with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { travel_to(now) { example.run } }
  end

  before do
    stub_request(:get, "#{base}/salon")
      .to_return(status: 200, body: '{"name":"Bella","timezone":"America/Sao_Paulo"}', headers: json)
  end

  describe '#perform' do
    subject(:card) { described_class.new(account: account, contact: contact).perform }

    context 'when the account is not linked to a salon' do
      it 'says so without calling belezaki' do
        expect(card).to eq(status: 'not_linked')
        expect(a_request(:get, /appointments/)).not_to have_been_made
      end
    end

    context 'when the account is linked through the integration hook' do
      before { create(:integrations_hook, :belezaki, account: account) }

      it 'refuses a contact without a phone number' do
        contact.update!(phone_number: nil)
        expect(card).to eq(status: 'no_phone')
        expect(a_request(:get, /appointments/)).not_to have_been_made
      end

      it 'splits the salon agenda into next, upcoming and history' do
        yesterday = appointment('a-yesterday', 'done', now - 1.day)
        upcoming = { client: client_json,
                     appointments: [yesterday,
                                    appointment('a-next', 'confirmed', now + 1.day),
                                    appointment('a-later', 'cancelled', now + 5.days)] }
        history = { client: client_json,
                    appointments: [appointment('a-old', 'no_show', now - 60.days), yesterday] }

        # The history window is a date range computed in the app's time zone,
        # which differs between this machine and CI; this example is about the
        # split, so match the two calls by shape (with/without a range), not
        # by the exact dates.
        stub_request(:get, "#{base}/appointments")
          .with(query: hash_including(phone: '+5531984956383'), headers: { 'X-Tenant-External-Id' => 'ext-1' }) do |req|
            !req.uri.query_values.key?('from')
          end
          .to_return(status: 200, body: upcoming.to_json, headers: json)
        stub_request(:get, "#{base}/appointments")
          .with(query: hash_including(phone: '+5531984956383')) do |req|
            req.uri.query_values.key?('from') && req.uri.query_values.key?('to')
          end
          .to_return(status: 200, body: history.to_json, headers: json)

        expect(card[:status]).to eq('ok')
        expect(card[:salon]).to eq(name: 'Bella', timezone: 'America/Sao_Paulo')
        expect(card[:client]).to eq('id' => 'c1', 'name' => 'Maria Souza', 'phone' => '5531984956383')
        expect(card[:next]['id']).to eq('a-next')
        expect(card[:upcoming].pluck('id')).to eq(%w[a-next a-later])
        expect(card[:history].pluck('id')).to eq(%w[a-yesterday a-old])
      end

      it 'has no next appointment when every future one is cancelled' do
        rows = { client: client_json, appointments: [appointment('a-later', 'cancelled', now + 5.days)] }
        stub_request(:get, "#{base}/appointments").with(query: hash_including(phone: '+5531984956383'))
                                                  .to_return(status: 200, body: rows.to_json, headers: json)

        expect(card[:next]).to be_nil
        expect(card[:upcoming].pluck('id')).to eq(%w[a-later])
      end

      it 'tells a contact the salon never saw apart from one with no bookings' do
        stub_request(:get, "#{base}/appointments").with(query: hash_including(phone: '+5531984956383'))
                                                  .to_return(status: 200, body: '{"client":null,"appointments":[]}', headers: json)

        expect(card).to eq(status: 'unknown_client', salon: { name: 'Bella', timezone: 'America/Sao_Paulo' })
      end

      it 'reports the salon being unreachable instead of raising' do
        stub_request(:get, "#{base}/appointments").with(query: hash_including(phone: '+5531984956383'))
                                                  .to_return(status: 503, body: '{"message":"down"}', headers: json)

        expect(card).to eq(status: 'unavailable', error: 'http_503')
      end
    end
  end
end
