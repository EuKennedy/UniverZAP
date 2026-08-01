# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ClaudeService do
  let(:service) { described_class.new(assistant: nil, account: nil) }

  describe 'retry policy' do
    let(:payload) { { model: 'claude-sonnet-4-5', max_tokens: 16, messages: [] } }

    before { allow(service).to receive(:sleep) }

    def http_response(code)
      instance_double(HTTParty::Response, code: code)
    end

    it 'retries a transient 5xx and returns the first successful response' do
      allow(service).to receive(:post_to_claude).and_return(http_response(500), http_response(200))

      response = service.send(:perform_request, 'key', payload)

      expect(response.code).to eq(200)
      expect(service).to have_received(:post_to_claude).twice
    end

    it 'retries a 429 rate limit' do
      allow(service).to receive(:post_to_claude).and_return(http_response(429), http_response(200))

      expect(service.send(:perform_request, 'key', payload).code).to eq(200)
    end

    it 'stops after MAX_RETRY_ATTEMPTS on persistent 5xx and surfaces the last response' do
      responses = Array.new(5) { http_response(503) }
      allow(service).to receive(:post_to_claude).and_return(*responses)

      response = service.send(:perform_request, 'key', payload)

      expect(response.code).to eq(503)
      expect(service).to have_received(:post_to_claude).exactly(described_class::MAX_RETRY_ATTEMPTS).times
    end

    it 'gives up after MAX_RETRY_ATTEMPTS on repeated network timeouts' do
      allow(service).to receive(:post_to_claude).and_raise(Net::ReadTimeout)

      expect { service.send(:perform_request, 'key', payload) }.to raise_error(Net::ReadTimeout)
      expect(service).to have_received(:post_to_claude).exactly(described_class::MAX_RETRY_ATTEMPTS).times
    end
  end

  describe 'error classification (Sprint 8)' do
    def failed_response(code)
      instance_double(HTTParty::Response, code: code, parsed_response: { 'error' => { 'message' => 'boom' } })
    end

    it 'classifies a persistent 5xx as transient so the caller can retry the turn later' do
      expect { service.send(:raise_upstream_error, failed_response(503)) }
        .to raise_error(described_class::TransientError)
    end

    it 'classifies a 429 rate limit as transient' do
      expect { service.send(:raise_upstream_error, failed_response(429)) }
        .to raise_error(described_class::TransientError)
    end

    it 'keeps a 4xx permanent so a bad request or key is never retried forever' do
      expect { service.send(:raise_upstream_error, failed_response(400)) }
        .to raise_error(an_instance_of(described_class::Error))
    end
  end
end
