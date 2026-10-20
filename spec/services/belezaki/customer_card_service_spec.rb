require 'rails_helper'

RSpec.describe Belezaki::CustomerCardService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5531984956383') }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  let(:now) { Time.zone.parse('2026-10-19 12:00:00 -03:00') }
  let(:client_json) { { id: 'c1', name: 'Maria Souza', phone: '5531984956383' } }
  let(:stats_json) do
    { visits: 2, no_shows: 1, total_spent_cents: 20_000, ticket_avg_cents: 10_000,
      last_visit_at: (now - 10.days).iso8601, recurrent: true, cashback_cents: 300 }
  end

  def appointment(id, status, start, extra = {})
    { id: id, status: status, service: 'Escova', professional: 'Ana',
      start: start.iso8601, end: (start + 1.hour).iso8601, can_cancel: true, can_reschedule: true }.merge(extra)
  end

  def stub_lookup(body, status: 200)
    stub_request(:get, "#{base}/clients/lookup")
      .with(query: { phone: '+5531984956383' }, headers: { 'X-Tenant-External-Id' => 'ext-1' })
      .to_return(status: status, body: body.to_json, headers: json)
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
        expect(a_request(:get, /lookup|appointments/)).not_to have_been_made
      end
    end

    context 'when the account is linked through the integration hook' do
      before { create(:integrations_hook, :belezaki, account: account) }

      it 'refuses a contact without a phone number' do
        contact.update!(phone_number: nil)
        expect(card).to eq(status: 'no_phone')
        expect(a_request(:get, /lookup|appointments/)).not_to have_been_made
      end

      it 'reads the whole profile in one call: stats, next chair, upcoming and history' do
        stub_lookup({
                      client: client_json, stats: stats_json,
                      upcoming: [appointment('a-cancelled', 'cancelled', now + 1.day),
                                 appointment('a-next', 'scheduled', now + 2.days, price_cents: 9000, needs_deposit: true),
                                 appointment('a-later', 'confirmed', now + 9.days, price_cents: 25_000, needs_deposit: false)],
                      history: [appointment('a-last', 'done', now - 10.days), appointment('a-miss', 'no_show', now - 40.days)]
                    })

        expect(card).to include(status: 'ok', salon: { name: 'Bella', timezone: 'America/Sao_Paulo' },
                                client: { 'id' => 'c1', 'name' => 'Maria Souza', 'phone' => '5531984956383' })
        expect(card[:stats]).to include('visits' => 2, 'no_shows' => 1, 'total_spent_cents' => 20_000, 'recurrent' => true)
        expect(card[:next]).to include('id' => 'a-next', 'status' => 'scheduled', 'needs_deposit' => true)
        expect(card[:upcoming].pluck('id')).to eq(%w[a-cancelled a-next a-later])
        expect(card[:history].pluck('id')).to eq(%w[a-last a-miss])
        expect(a_request(:get, "#{base}/appointments")).not_to have_been_made
      end

      it 'has no next appointment when every future one is cancelled' do
        stub_lookup({ client: client_json, stats: stats_json,
                      upcoming: [appointment('a-later', 'cancelled', now + 5.days)], history: [] })

        expect(card[:next]).to be_nil
        expect(card[:upcoming].pluck('id')).to eq(%w[a-later])
      end

      it 'tells a contact the salon never saw apart from one with no bookings' do
        stub_lookup({ client: nil, stats: nil, upcoming: [], history: [] })

        expect(card).to eq(status: 'unknown_client', salon: { name: 'Bella', timezone: 'America/Sao_Paulo' })
      end

      it 'reports the salon being unreachable instead of raising' do
        stub_lookup({ message: 'down' }, status: 503)

        expect(card).to eq(status: 'unavailable', error: 'http_503')
      end

      # A salon still on the version before clients/lookup answers 404 for the
      # route; the agenda alone is better than a blank card until it updates.
      context 'when the salon does not have the lookup route yet' do
        before do
          stub_lookup({ statusCode: 404, message: 'Cannot GET /api/agent/v1/clients/lookup', error: 'Not Found' }, status: 404)
        end

        it 'falls back to the agenda split into next, upcoming and history, without stats' do
          yesterday = appointment('a-yesterday', 'done', now - 1.day)
          upcoming = { client: client_json,
                       appointments: [yesterday,
                                      appointment('a-next', 'confirmed', now + 1.day),
                                      appointment('a-later', 'cancelled', now + 5.days)] }
          history = { client: client_json,
                      appointments: [appointment('a-old', 'no_show', now - 60.days), yesterday] }

          # Matched by shape (with/without a date range): the range is computed in
          # the app's time zone, which differs between this machine and CI.
          stub_request(:get, "#{base}/appointments")
            .with(query: hash_including(phone: '+5531984956383')) { |req| !req.uri.query_values.key?('from') }
            .to_return(status: 200, body: upcoming.to_json, headers: json)
          stub_request(:get, "#{base}/appointments")
            .with(query: hash_including(phone: '+5531984956383')) { |req| req.uri.query_values.key?('from') }
            .to_return(status: 200, body: history.to_json, headers: json)

          expect(card[:status]).to eq('ok')
          expect(card[:stats]).to be_nil
          expect(card[:next]['id']).to eq('a-next')
          expect(card[:upcoming].pluck('id')).to eq(%w[a-next a-later])
          expect(card[:history].pluck('id')).to eq(%w[a-yesterday a-old])
        end

        it 'still tells an unknown contact apart' do
          stub_request(:get, "#{base}/appointments").with(query: hash_including(phone: '+5531984956383'))
                                                    .to_return(status: 200, body: '{"client":null,"appointments":[]}', headers: json)

          expect(card).to eq(status: 'unknown_client', salon: { name: 'Bella', timezone: 'America/Sao_Paulo' })
        end
      end
    end
  end
end
