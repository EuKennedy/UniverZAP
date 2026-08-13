require 'rails_helper'

RSpec.describe Ai::Belezaki::AgentClient do
  let(:client) { described_class.new(external_id: 'ext-1', api_key: 'k') }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }

  before { allow(client).to receive(:sleep) }

  # The Nest app mounts everything under a global `api` prefix, so `/agent/v1` is
  # a 404 from the proxy — which is why this integration looked silent rather
  # than broken.
  it 'calls under the api prefix' do
    stub_request(:get, "#{base}/salon").to_return(status: 200, body: '{"name":"Bella"}')

    expect(client.salon['name']).to eq('Bella')
  end

  it 'sends the shared key and the salon on every call' do
    stub_request(:get, "#{base}/services").to_return(status: 200, body: '{"services":[]}')

    client.services

    expect(a_request(:get, "#{base}/services")
      .with(headers: { 'X-Univerzap-Agent-Key' => 'k', 'X-Tenant-External-Id' => 'ext-1' })).to have_been_made
  end

  describe 'the three error shapes' do
    # A taken slot is a normal turn in a conversation, not a failure — but only
    # if the code survives. Matching on the message is what the field spec bans.
    it 'keeps the code of a slot conflict' do
      stub_request(:post, "#{base}/appointments")
        .to_return(status: 409, body: '{"error":"slot_taken","message":"Horário não está mais disponível."}')

      expect { client.create_appointment({}) }.to raise_error(described_class::Error) { |e|
        expect(e.code).to eq('slot_taken')
      }
    end

    it 'recognises a validation array as validation, not as a message' do
      body = '{"message":["idempotency_key must be longer"],"error":"Bad Request","statusCode":400}'
      stub_request(:post, "#{base}/appointments").to_return(status: 400, body: body)

      expect { client.create_appointment({}) }.to raise_error(described_class::Error) { |e|
        expect(e.code).to eq('validation_failed')
        expect(e.validation).to eq(['idempotency_key must be longer'])
      }
    end

    it 'falls back to the http status for the plain Nest shape' do
      stub_request(:get, "#{base}/salon")
        .to_return(status: 404, body: '{"message":"Salão não encontrado.","error":"Not Found","statusCode":404}')

      expect { client.salon }.to raise_error(described_class::Error) { |e|
        expect(e.code).to eq('http_404')
        expect(e.status).to eq(404)
      }
    end
  end

  describe 'the routes that change an existing appointment' do
    # POST, so the salon answers 201. A success check written as `== 200` would
    # turn every completed cancellation into a silent error.
    it 'treats the 201 of a cancellation as success' do
      stub_request(:post, "#{base}/appointments/a1/cancel")
        .to_return(status: 201, body: '{"changed":true}', headers: { 'Content-Type' => 'application/json' })

      expect(client.cancel_appointment('a1', { client_phone: '+55319' })['changed']).to be(true)
    end

    it 'moves an appointment with PATCH' do
      stub_request(:patch, "#{base}/appointments/a1")
        .to_return(status: 200, body: '{"changed":true}', headers: { 'Content-Type' => 'application/json' })

      expect(client.reschedule_appointment('a1', { start: 'x' })['changed']).to be(true)
    end

    # Only the parameters the salon whitelists: an extra one is a 400 now, not
    # something it ignores.
    it 'sends only the query parameters the salon accepts' do
      stub_request(:get, "#{base}/appointments").with(query: { phone: '+55319' })
        .to_return(status: 200, body: '{"appointments":[]}', headers: { 'Content-Type' => 'application/json' })

      expect(client.appointments(phone: '+55319')['appointments']).to eq([])
    end
  end

  describe 'retry' do
    it 'retries a 500 and gives up after two attempts' do
      stub_request(:get, "#{base}/salon").to_return(status: 500, body: '{"message":"boom"}')

      expect { client.salon }.to raise_error(described_class::Error)
      expect(a_request(:get, "#{base}/salon")).to have_been_made.twice
    end

    it 'retries a 429, since the bucket is shared by every salon' do
      stub_request(:get, "#{base}/salon")
        .to_return({ status: 429, body: '{"message":"slow down"}' }, { status: 200, body: '{"name":"Bella"}' })

      expect(client.salon['name']).to eq('Bella')
    end

    # A 4xx is the server saying the request itself is wrong. Repeating it is
    # waste, and on a write it is a second appointment waiting to happen.
    it 'does not retry a 400' do
      stub_request(:get, "#{base}/salon").to_return(status: 400, body: '{"message":"bad"}')

      expect { client.salon }.to raise_error(described_class::Error)
      expect(a_request(:get, "#{base}/salon")).to have_been_made.once
    end

    it 'does not retry a taken slot' do
      stub_request(:post, "#{base}/appointments")
        .to_return(status: 409, body: '{"error":"slot_taken","message":"x"}')

      expect { client.create_appointment({}) }.to raise_error(described_class::Error)
      expect(a_request(:post, "#{base}/appointments")).to have_been_made.once
    end
  end
end
