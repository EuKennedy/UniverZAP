# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ClaudeService do
  let(:service) { described_class.new(assistant: nil, account: nil) }

  # Anthropic charges a cached prefix at a tenth of the input price, but only
  # when it arrives as system BLOCKS carrying a cache breakpoint.
  describe 'prompt caching' do
    it 'sends a plain string system prompt unchanged, with no cache breakpoint' do
      expect(service.send(:build_system, 'regras')).to eq('regras')
    end

    it 'splits segments into blocks and caches everything before the last one' do
      blocks = service.send(:build_system, ['regras estaveis', 'contexto do turno'])

      expect(blocks.first).to eq(
        type: 'text', text: 'regras estaveis', cache_control: { type: 'ephemeral' }
      )
      expect(blocks.last).to eq(type: 'text', text: 'contexto do turno')
    end

    it 'does not mark a breakpoint when there is nothing stable to cache' do
      expect(service.send(:build_system, ['so isso', ''])).to eq('so isso')
    end

    # The turn-specific tail carries the retrieved knowledge base, and a
    # tool-using turn re-sends it on every iteration. Six iterations meant six
    # full-price copies of it until this breakpoint existed.
    it 'caches the turn tail too when the caller expects more calls in seconds' do
      blocks = service.send(:build_system, ['regras estaveis', 'contexto do turno'], true)

      expect(blocks.last).to eq(
        type: 'text', text: 'contexto do turno', cache_control: { type: 'ephemeral' }
      )
    end

    it 'leaves messages untouched unless the caller asks for a breakpoint' do
      messages = [{ role: 'user', content: 'oi' }]

      expect(service.send(:cache_messages, messages, false)).to eq(messages)
    end

    it 'marks the last message so the conversation so far is read back from cache' do
      messages = [{ role: 'user', content: 'oi' }, { role: 'user', content: [{ type: 'text', text: 'tudo bem?' }] }]

      cached = service.send(:cache_messages, messages, true)

      expect(cached.first).to eq(role: 'user', content: 'oi')
      expect(cached.last[:content].last).to include(cache_control: { type: 'ephemeral' })
    end

    it 'wraps a plain string message into a block before marking it' do
      cached = service.send(:cache_messages, [{ role: 'user', content: 'oi' }], true)

      expect(cached.last[:content]).to eq(
        [{ type: 'text', text: 'oi', cache_control: { type: 'ephemeral' } }]
      )
    end

    it 'prices cached tokens at the cache rate instead of full input' do
      usage = { 'cache_read_input_tokens' => 10_000, 'cache_creation_input_tokens' => 0 }
      cached = service.send(:cost_cents_brl, 'claude-sonnet-4-5', [0, 100], usage)
      uncached = service.send(:cost_cents_brl, 'claude-sonnet-4-5', [10_000, 100], {})

      expect(cached).to be < uncached
    end
  end

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
