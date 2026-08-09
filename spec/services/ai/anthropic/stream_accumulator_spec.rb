require 'rails_helper'

RSpec.describe Ai::Anthropic::StreamAccumulator do
  subject(:accumulator) { described_class.new }

  def frame(type, payload = {})
    "event: #{type}\ndata: #{payload.merge(type: type).to_json}\n\n"
  end

  def feed(*frames)
    frames.each { |raw| accumulator.ingest(raw) }
  end

  def message_start(usage = {})
    frame('message_start', message: {
            id: 'msg_1', model: 'claude-sonnet-4-5', role: 'assistant',
            usage: { input_tokens: 120, output_tokens: 1 }.merge(usage)
          })
  end

  describe 'a plain text answer' do
    before do
      feed(
        message_start,
        frame('content_block_start', index: 0, content_block: { type: 'text', text: '' }),
        frame('ping'),
        frame('content_block_delta', index: 0, delta: { type: 'text_delta', text: 'Bom ' }),
        frame('content_block_delta', index: 0, delta: { type: 'text_delta', text: 'dia!' }),
        frame('content_block_stop', index: 0),
        frame('message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 42 }),
        frame('message_stop')
      )
    end

    it 'rebuilds the same shape the non-streaming endpoint returns' do
      message = accumulator.to_message
      expect(message['content']).to eq([{ 'type' => 'text', 'text' => 'Bom dia!' }])
      expect(message['stop_reason']).to eq('end_turn')
      expect(message['model']).to eq('claude-sonnet-4-5')
    end

    # The ledger bills against these, so losing them would silently make every
    # streamed call free.
    it 'keeps the input usage from message_start and the output usage from message_delta' do
      usage = accumulator.to_message['usage']
      expect(usage['input_tokens']).to eq(120)
      expect(usage['output_tokens']).to eq(42)
    end

    it 'reports no error' do
      expect(accumulator.error).to be_nil
    end
  end

  describe 'cache counters' do
    it 'carries them through, because the discount is passed to the operator' do
      feed(message_start(cache_creation_input_tokens: 900, cache_read_input_tokens: 4_100))
      usage = accumulator.to_message['usage']
      expect(usage['cache_creation_input_tokens']).to eq(900)
      expect(usage['cache_read_input_tokens']).to eq(4_100)
    end
  end

  describe 'a tool call' do
    before do
      feed(
        message_start,
        frame('content_block_start', index: 0,
                                     content_block: { type: 'tool_use', id: 'toolu_1', name: 'consultar_preco', input: {} }),
        frame('content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: '{"produto":' }),
        frame('content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: '"progressiva"}' }),
        frame('content_block_stop', index: 0),
        frame('message_delta', delta: { stop_reason: 'tool_use' }, usage: { output_tokens: 30 })
      )
    end

    it 'reassembles the input JSON that arrived in fragments' do
      block = accumulator.to_message['content'].first
      expect(block['type']).to eq('tool_use')
      expect(block['name']).to eq('consultar_preco')
      expect(block['input']).to eq({ 'produto' => 'progressiva' })
    end
  end

  describe 'a truncated tool input' do
    before do
      feed(
        message_start,
        frame('content_block_start', index: 0, content_block: { type: 'tool_use', id: 'toolu_1', name: 'agendar', input: {} }),
        frame('content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: '{"horario":' }),
        frame('content_block_stop', index: 0)
      )
    end

    # Half the arguments is worse than none: an empty input makes the executor
    # fail loudly instead of booking the wrong slot.
    it 'leaves the input empty rather than guessing' do
      expect(accumulator.to_message['content'].first['input']).to eq({})
    end
  end

  describe 'text and tool_use in the same answer' do
    it 'keeps the blocks in index order' do
      feed(
        message_start,
        frame('content_block_start', index: 1, content_block: { type: 'tool_use', id: 't', name: 'x', input: {} }),
        frame('content_block_start', index: 0, content_block: { type: 'text', text: '' }),
        frame('content_block_delta', index: 0, delta: { type: 'text_delta', text: 'deixa eu ver' }),
        frame('content_block_stop', index: 0),
        frame('content_block_stop', index: 1)
      )
      expect(accumulator.to_message['content'].map { |b| b['type'] }).to eq(%w[text tool_use])
    end
  end

  describe 'a mid-stream error frame' do
    it 'is surfaced instead of returning a half-written answer as if it were complete' do
      feed(
        message_start,
        frame('content_block_start', index: 0, content_block: { type: 'text', text: '' }),
        frame('content_block_delta', index: 0, delta: { type: 'text_delta', text: 'metade' }),
        frame('error', error: { type: 'overloaded_error', message: 'Overloaded' })
      )
      expect(accumulator.error).to eq({ 'type' => 'overloaded_error', 'message' => 'Overloaded' })
    end
  end

  describe 'a malformed frame' do
    it 'is dropped without costing the answer it arrived with' do
      feed(
        message_start,
        "event: content_block_delta\ndata: {not json\n\n",
        frame('content_block_start', index: 0, content_block: { type: 'text', text: 'ok' }),
        frame('content_block_stop', index: 0)
      )
      expect(accumulator.to_message['content'].first['text']).to eq('ok')
    end
  end
end
