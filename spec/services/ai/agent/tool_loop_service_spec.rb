require 'rails_helper'

RSpec.describe Ai::Agent::ToolLoopService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:claude) { instance_double(Ai::ClaudeService) }
  let(:executor) { instance_double(Ai::Belezaki::SchedulingTools) }
  let(:tools) { [{ name: 'listar_servicos' }] }
  let(:messages) { [{ role: 'user', content: 'quais serviços?' }] }

  before { allow(Ai::ClaudeService).to receive(:new).and_return(claude) }

  def run
    described_class.new(
      assistant: assistant, conversation: conversation, messages: messages,
      system: 'sys', tools: tools, tool_executor: executor
    ).perform
  end

  it 'executes the requested tool then returns the final text reply' do
    tool_use = { 'id' => 'tu_1', 'name' => 'listar_servicos', 'input' => {} }
    allow(claude).to receive(:chat).and_return(
      { content: '', tool_uses: [tool_use], stop_reason: 'tool_use', raw: { 'content' => [{ 'type' => 'tool_use', 'id' => 'tu_1' }] } },
      { content: 'Temos progressiva e botox.', tool_uses: [], stop_reason: 'end_turn', raw: { 'content' => [] } }
    )
    allow(executor).to receive(:call).with('listar_servicos', {}).and_return('{"services":[]}')

    result = run

    expect(executor).to have_received(:call).with('listar_servicos', {})
    expect(result[:content]).to eq('Temos progressiva e botox.')
  end

  it 'returns immediately when Claude needs no tools' do
    allow(claude).to receive(:chat).and_return({ content: 'Oi!', tool_uses: [], stop_reason: 'end_turn' })

    expect(run[:content]).to eq('Oi!')
  end

  context 'when the turn budget runs out' do
    let(:tool_use) { { 'id' => 'tu_1', 'name' => 'listar_servicos', 'input' => {} } }
    let(:calls) { [] }

    before do
      # A negative budget puts the deadline in the past, so the very first tool
      # result already lands over time.
      stub_const("#{described_class}::TURN_BUDGET_SECONDS", -1)
      responses = [
        { content: '', tool_uses: [tool_use], stop_reason: 'tool_use', raw: { 'content' => [] } },
        { content: 'Com o que tenho aqui, temos progressiva.', tool_uses: [], stop_reason: 'end_turn' }
      ]
      allow(claude).to receive(:chat) do |**kwargs|
        calls << kwargs
        responses.shift
      end
      allow(executor).to receive(:call).and_return('{"services":[]}')
    end

    # Silence is what the customer used to get. A worse answer is still an answer.
    it 'forces a final answer instead of starting another iteration' do
      expect(run[:content]).to eq('Com o que tenho aqui, temos progressiva.')
      expect(calls.size).to eq(2)
    end

    it 'takes the tools off the table so Claude cannot ask for another round' do
      run

      expect(calls.first).not_to include(:tool_choice)
      expect(calls.last[:tool_choice]).to eq({ type: 'none' })
    end
  end
end
