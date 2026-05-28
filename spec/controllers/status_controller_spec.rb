# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'StatusController#show', type: :request do
  let(:redis_double) { instance_double(Redis, ping: 'PONG') }

  before do
    allow(Redis).to receive(:new).and_return(redis_double)
  end

  context 'when every dependency answers' do
    before do
      stats_double = instance_double(Sidekiq::Stats, processes_size: 1)
      queue_double = instance_double(Sidekiq::Queue, latency: 0.5)
      allow(Sidekiq::Stats).to receive(:new).and_return(stats_double)
      allow(Sidekiq::Queue).to receive(:new).with('default').and_return(queue_double)
    end

    it 'returns 200 + JSON summary when requested as JSON' do
      get '/status.json'
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['overall']).to eq('operational')
      expect(body['services'].keys).to match_array(%w[database redis sidekiq])
    end

    it 'renders the HTML status page by default' do
      get '/status'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Status do sistema')
      expect(response.body).to include('operacionais')
    end
  end

  context 'when Sidekiq has no workers' do
    before do
      stats_double = instance_double(Sidekiq::Stats, processes_size: 0)
      allow(Sidekiq::Stats).to receive(:new).and_return(stats_double)
    end

    it 'returns 503 in JSON mode' do
      get '/status.json'
      expect(response).to have_http_status(:service_unavailable)
      body = response.parsed_body
      expect(body['overall']).to eq('degraded')
      expect(body['services']['sidekiq']['status']).to eq('down')
    end
  end
end
