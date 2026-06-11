# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ClaudeService do
  subject(:service) { described_class.new(assistant: nil, account: nil) }

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
end
