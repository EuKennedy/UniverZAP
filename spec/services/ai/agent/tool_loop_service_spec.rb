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

  # A reply that promises a lookup and calls nothing leaves the customer waiting
  # for something that will never happen: there is no later turn in which the
  # agent remembers to do it.
  describe 'a promised lookup that was never made' do
    it 'forces the call the reply said it was making' do
      tool_use = { 'id' => 'tu_1', 'name' => 'listar_servicos', 'input' => {} }
      allow(claude).to receive(:chat).and_return(
        { content: 'Deixa eu confirmar o valor certinho pra você.', tool_uses: [], stop_reason: 'end_turn' },
        { content: '', tool_uses: [tool_use], stop_reason: 'tool_use', raw: { 'content' => [] } },
        { content: 'Custa R$ 219.', tool_uses: [], stop_reason: 'end_turn', raw: { 'content' => [] } }
      )
      allow(executor).to receive(:call).and_return('{"price":219}')

      expect(run[:content]).to eq('Custa R$ 219.')
      expect(claude).to have_received(:chat).with(hash_including(tool_choice: { type: 'any' })).once
    end

    it 'forces the call when the model writes the markup instead of using it' do
      tool_use = { 'id' => 'tu_1', 'name' => 'listar_servicos', 'input' => {} }
      allow(claude).to receive(:chat).and_return(
        { content: 'Opa! <tool_uses><tool_use><tool_name>listar_servicos</tool_name></tool_use></tool_uses>',
          tool_uses: [], stop_reason: 'end_turn' },
        { content: '', tool_uses: [tool_use], stop_reason: 'tool_use', raw: { 'content' => [] } },
        { content: 'Temos progressiva.', tool_uses: [], stop_reason: 'end_turn', raw: { 'content' => [] } }
      )
      allow(executor).to receive(:call).and_return('{}')

      expect(run[:content]).to eq('Temos progressiva.')
    end

    # Last line of defence: the customer must never be shown raw markup.
    it 'strips the markup when even the forced call comes back with it' do
      allow(claude).to receive(:chat).and_return(
        { content: 'Temos sim <tool_uses><tool_use>x</tool_use></tool_uses> em estoque',
          tool_uses: [], stop_reason: 'end_turn' }
      )

      expect(run[:content]).to eq('Temos sim em estoque')
    end

    it 'leaves an ordinary reply alone' do
      allow(claude).to receive(:chat).and_return({ content: 'Oi, tudo bem?', tool_uses: [], stop_reason: 'end_turn' })

      run

      expect(claude).to have_received(:chat).once
    end

    # This used to be allowed through, on the theory that a promise made after a
    # tool had run was already kept by it. It was not: "já te confirmo" on the
    # second iteration is about the NEXT lookup, and no turn is left to make it.
    # This exact shape reached a real customer, who never heard from us again.
    it 'forces the call even when a tool has already run this turn' do
      tool_use = { 'id' => 'tu_1', 'name' => 'listar_servicos', 'input' => {} }
      allow(claude).to receive(:chat).and_return(
        { content: '', tool_uses: [tool_use], stop_reason: 'tool_use', raw: { 'content' => [] } },
        { content: 'Já te confirmo o restante.', tool_uses: [], stop_reason: 'end_turn', raw: { 'content' => [] } },
        { content: '', tool_uses: [tool_use], stop_reason: 'tool_use', raw: { 'content' => [] } },
        { content: 'O restante sai por R$ 90.', tool_uses: [], stop_reason: 'end_turn', raw: { 'content' => [] } }
      )
      allow(executor).to receive(:call).and_return('{}')

      expect(run[:content]).to eq('O restante sai por R$ 90.')
      expect(claude).to have_received(:chat).with(hash_including(tool_choice: { type: 'any' }))
    end

    # Forcing is the fix; this is what is left when forcing itself fails. Going
    # quiet puts the conversation in front of a human, which is recoverable —
    # telling the customer someone is checking and then never speaking again is
    # not.
    it 'goes quiet rather than promising, when the forced call itself fails' do
      calls = 0
      allow(claude).to receive(:chat) do
        calls += 1
        raise Ai::ClaudeService::Error, 'overloaded' if calls > 1

        { content: 'Perfeito, deixa eu buscar aqui pra você!', tool_uses: [], stop_reason: 'end_turn' }
      end

      expect { run }.to raise_error(described_class::PromiseUnfulfilled)
    end
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
