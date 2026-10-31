require 'rails_helper'

RSpec.describe Belezaki::CustomerSummariesService do
  let(:account) { create(:account) }
  let(:maria) { create(:contact, account: account, phone_number: '+5531984956383') }
  let(:ana) { create(:contact, account: account, phone_number: '+5531984956384') }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:now) { Time.zone.parse('2026-10-19 12:00:00 -03:00') }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  def appointment(status, start, service, professional)
    { id: "#{service}-#{start}", status: status, service: service, professional: professional, start: start.iso8601 }
  end

  def lookup_body
    { client: { id: 'c1', name: 'Maria' },
      stats: { visits: 3, no_shows: 1, total_spent_cents: 45_000, last_visit_at: (now - 5.days).iso8601 },
      upcoming: [appointment('confirmed', now + 2.days, 'Escova', 'Ana')],
      history: [appointment('done', now - 5.days, 'Corte', 'Bianca'), appointment('no_show', now - 7.days, 'Manicure', 'Carla'),
                appointment('done', now - 9.days, 'Coloração', 'Bianca'), appointment('done', now - 20.days, 'Corte', 'Ana')] }
  end

  def stub_lookup(phone, status: 200, body: lookup_body)
    stub_request(:get, "#{base}/clients/lookup").with(query: { phone: phone })
                                                .to_return(status: status, body: body.to_json, headers: json)
  end

  around do |example|
    with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { travel_to(now) { example.run } }
  end

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def summaries(*contacts)
    described_class.new(account: account, contacts: contacts).perform
  end

  it 'says not linked for every contact without calling belezaki' do
    expect(summaries(maria, ana).values).to all(eq(status: 'not_linked'))
    expect(a_request(:get, /lookup/)).not_to have_been_made
  end

  context 'when the salon is connected' do
    before do
      stub_request(:get, "#{base}/salon")
        .to_return(status: 200, body: '{"name":"Bella","timezone":"America/Sao_Paulo"}', headers: json)
      create(:integrations_hook, :belezaki, account: account)
      allow_any_instance_of(Ai::Belezaki::AgentClient).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    end

    it 'reduces the card to what the list shows' do
      stub_lookup('+5531984956383')

      expect(summaries(maria)[maria.id]).to include(
        status: 'ok', professional: 'Bianca', last_services: %w[Corte Coloração],
        total_spent_cents: 45_000, visits: 3, no_shows: 1
      )
      expect(summaries(maria)[maria.id][:next]).to include('service' => 'Escova', 'professional' => 'Ana')
    end

    it 'answers from the cache on the next batch' do
      lookup = stub_lookup('+5531984956383')

      2.times { summaries(maria) }

      expect(lookup).to have_been_requested.once
    end

    it 'gives up on the batch at the first failure and caches nothing' do
      failing = stub_lookup('+5531984956383', status: 503, body: { message: 'down' })
      second = stub_lookup('+5531984956384')

      result = summaries(maria, ana)

      expect(result.values).to all(eq(status: 'unavailable'))
      expect(failing).to have_been_requested.twice
      expect(second).not_to have_been_requested
      expect(cache.read("belezaki/summary/#{account.id}/#{maria.id}/#{maria.phone_number}")).to be_nil
    end
  end
end
