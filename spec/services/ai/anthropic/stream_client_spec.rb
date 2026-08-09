require 'rails_helper'

RSpec.describe Ai::Anthropic::StreamClient do
  subject(:client) do
    described_class.new(
      url: 'https://api.anthropic.com/v1/messages',
      headers: { 'x-api-key' => 'sk-test', 'content-type' => 'application/json' },
      payload: { model: 'claude-sonnet-4-5', max_tokens: 1024, messages: [{ role: 'user', content: 'oi' }] }
    )
  end

  let(:endpoint) { 'https://api.anthropic.com/v1/messages' }
  let(:happy_stream) do
    [
      frame('message_start', message: { id: 'msg_1', model: 'claude-sonnet-4-5', role: 'assistant',
                                        usage: { input_tokens: 10, output_tokens: 1 } }),
      frame('content_block_start', index: 0, content_block: { type: 'text', text: '' }),
      frame('content_block_delta', index: 0, delta: { type: 'text_delta', text: 'Oi!' }),
      frame('content_block_stop', index: 0),
      frame('message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 5 }),
      frame('message_stop')
    ].join
  end

  def frame(type, payload = {})
    "event: #{type}\ndata: #{payload.merge(type: type).to_json}\n\n"
  end

  describe 'the request it sends' do
    before { stub_request(:post, endpoint).to_return(status: 200, body: happy_stream) }

    it 'asks for a stream and forwards the caller headers' do
      client.perform
      expect(
        a_request(:post, endpoint).with(
          headers: { 'x-api-key' => 'sk-test', 'accept' => 'text/event-stream' },
          body: /"stream":true/
        )
      ).to have_been_made
    end
  end

  describe 'a successful stream' do
    before { stub_request(:post, endpoint).to_return(status: 200, body: happy_stream) }

    it 'quacks like the non-streaming response every caller already expects' do
      response = client.perform
      expect(response.code).to eq(200)
      expect(response).to be_success
      expect(response.parsed_response['content']).to eq([{ 'type' => 'text', 'text' => 'Oi!' }])
      expect(response.parsed_response['usage']['output_tokens']).to eq(5)
    end
  end

  describe 'an HTTP error' do
    before do
      stub_request(:post, endpoint).to_return(
        status: 400, body: { error: { type: 'invalid_request_error', message: 'bad model' } }.to_json
      )
    end

    # Ai::ClaudeService#raise_upstream_error reads parsed_response['error'], and
    # the invocation log reads body, so both have to survive.
    it 'carries the status, the parsed error and the raw body through' do
      response = client.perform
      expect(response.code).to eq(400)
      expect(response).not_to be_success
      expect(response.parsed_response.dig('error', 'message')).to eq('bad model')
      expect(response.body).to include('bad model')
    end
  end

  describe 'a mid-stream error frame' do
    before do
      body = frame('message_start', message: { id: 'msg_1', model: 'claude-sonnet-4-5', usage: {} }) +
             frame('error', error: { type: 'overloaded_error', message: 'Overloaded' })
      stub_request(:post, endpoint).to_return(status: 200, body: body)
    end

    # Anthropic reports this on an HTTP 200. Left as 200 it would be logged as a
    # successful empty reply; mapped to 529 it lands in ClaudeService's
    # retryable band and becomes a TransientError the job can retry.
    it 'is translated back into a retryable status code' do
      response = client.perform
      expect(response.code).to eq(529)
      expect(response).not_to be_success
      expect(response.parsed_response.dig('error', 'type')).to eq('overloaded_error')
    end
  end

  describe 'frames split across TCP chunks' do
    # The wire does not respect frame boundaries, and a multi-byte character cut
    # in half used to be the classic way to blow up an SSE reader.
    it 'holds the tail of a partial frame until the rest arrives' do
      accumulator = Ai::Anthropic::StreamAccumulator.new
      buffer = String.new(encoding: Encoding::BINARY)
      chunks = happy_stream.dup.force_encoding(Encoding::BINARY).chars.each_slice(37).map(&:join)
      chunks.each do |chunk|
        buffer << chunk
        client.send(:drain, buffer, accumulator)
      end
      expect(accumulator.to_message['content']).to eq([{ 'type' => 'text', 'text' => 'Oi!' }])
    end

    it 'does not break on a multi-byte character straddling the boundary' do
      accumulator = Ai::Anthropic::StreamAccumulator.new
      body = frame('content_block_start', index: 0, content_block: { type: 'text', text: 'ação é ótimo' })
      buffer = String.new(encoding: Encoding::BINARY)
      body.dup.force_encoding(Encoding::BINARY).chars.each_slice(5).map(&:join).each do |chunk|
        buffer << chunk
        client.send(:drain, buffer, accumulator)
      end
      expect(accumulator.to_message['content'].first['text']).to eq('ação é ótimo')
    end
  end
end
