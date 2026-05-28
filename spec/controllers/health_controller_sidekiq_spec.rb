# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HealthController#sidekiq', type: :request do
  describe 'GET /health/sidekiq' do
    context 'when no Sidekiq workers are alive' do
      before do
        stats_double = instance_double(Sidekiq::Stats, processes_size: 0)
        allow(Sidekiq::Stats).to receive(:new).and_return(stats_double)
      end

      it 'returns 503 so external monitors page on-call' do
        get '/health/sidekiq'
        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['sidekiq']).to eq('down')
      end
    end

    context 'when workers are alive and queue latency is low' do
      before do
        stats_double = instance_double(Sidekiq::Stats, processes_size: 2)
        queue_double = instance_double(Sidekiq::Queue, latency: 1.0)
        allow(Sidekiq::Stats).to receive(:new).and_return(stats_double)
        allow(Sidekiq::Queue).to receive(:new).with('default').and_return(queue_double)
      end

      it 'returns 200 with ok status' do
        get '/health/sidekiq'
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['sidekiq']).to eq('ok')
      end
    end

    context 'when queue latency exceeds the 60s budget' do
      before do
        stats_double = instance_double(Sidekiq::Stats, processes_size: 2)
        queue_double = instance_double(Sidekiq::Queue, latency: 120.0)
        allow(Sidekiq::Stats).to receive(:new).and_return(stats_double)
        allow(Sidekiq::Queue).to receive(:new).with('default').and_return(queue_double)
      end

      it 'returns 503 to flag a stuck worker' do
        get '/health/sidekiq'
        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['sidekiq']).to eq('down')
      end
    end
  end
end
