require 'rails_helper'

RSpec.describe AutomationRules::WaitingScanner do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:action_service) { instance_double(AutomationRules::ActionService, perform: nil) }

  let!(:rule) do
    create(:automation_rule, account: account, event_name: 'conversation_waiting',
                             conditions: [{ 'attribute_key' => 'waiting_minutes', 'filter_operator' => 'is_greater_than',
                                            'values' => ['15'], 'query_operator' => nil }],
                             actions: [{ 'action_name' => 'assign_least_busy', 'action_params' => [] }])
  end

  def waiting(minutes, awaiting_reply: true, status: :open)
    create(:conversation, account: account, inbox: inbox, status: status).tap do |conversation|
      conversation.update!(waiting_since: minutes.minutes.ago, awaiting_reply: awaiting_reply)
    end
  end

  before do
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
  end

  it 'runs the rule on a conversation the customer has been waiting on for longer than the threshold' do
    conversation = waiting(20)

    described_class.new.perform

    expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, conversation)
    expect(AutomationRuleFiring.where(automation_rule: rule, conversation: conversation).count).to eq(1)
  end

  it 'leaves conversations under the threshold alone' do
    waiting(5)

    described_class.new.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end

  it 'ignores conversations where the agent already has the last word, or that are not open' do
    waiting(30, awaiting_reply: false)
    waiting(30, status: :resolved)

    described_class.new.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end

  it 'fires once per waiting period and again when the customer waits anew' do
    conversation = waiting(20)

    described_class.new.perform
    described_class.new.perform
    expect(AutomationRules::ActionService).to have_received(:new).once

    conversation.update!(waiting_since: 40.minutes.ago)
    described_class.new.perform
    expect(AutomationRules::ActionService).to have_received(:new).twice
  end

  it 'still applies the other conditions of the rule' do
    rule.update!(conditions: [
                   { 'attribute_key' => 'waiting_minutes', 'filter_operator' => 'is_greater_than', 'values' => ['15'], 'query_operator' => 'AND' },
                   { 'attribute_key' => 'priority', 'filter_operator' => 'equal_to', 'values' => ['urgent'], 'query_operator' => nil }
                 ])
    waiting(20)

    described_class.new.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end

  it 'skips rules without a waiting threshold instead of firing on everything' do
    rule.update!(conditions: [])
    waiting(20)

    described_class.new.perform

    expect(AutomationRules::ActionService).not_to have_received(:new)
  end

  describe 'conversations open for too long (resolution SLA)' do
    let!(:sla_rule) do
      create(:automation_rule, account: account, event_name: 'conversation_unresolved',
                               conditions: [{ 'attribute_key' => 'open_minutes', 'filter_operator' => 'is_greater_than',
                                              'values' => ['60'], 'query_operator' => nil }],
                               actions: [{ 'action_name' => 'change_priority', 'action_params' => ['urgent'] }])
    end

    before { rule.update!(active: false) }

    def opened(minutes_ago, status: :open)
      create(:conversation, account: account, inbox: inbox, status: status, created_at: minutes_ago.minutes.ago)
    end

    it 'fires once on a conversation open for longer than the threshold' do
      conversation = opened(120)

      described_class.new.perform
      described_class.new.perform

      expect(AutomationRules::ActionService).to have_received(:new).with(sla_rule, account, conversation).once
    end

    it 'leaves recent or resolved conversations alone' do
      opened(10)
      opened(120, status: :resolved)

      described_class.new.perform

      expect(AutomationRules::ActionService).not_to have_received(:new)
    end
  end

  describe 'chatflows triggered by no reply' do
    let(:chatflow) do
      Chatflow.create!(account: account, name: 'Sem resposta', inbox: inbox, status: :active,
                       trigger_type: :no_reply, trigger_config: { 'no_reply_minutes' => 10 })
    end
    let!(:node) { ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message, config: { 'text' => 'Já te atendo!' }) }

    before { chatflow.update!(start_node: node) }

    it 'starts the flow once per waiting period' do
      conversation = waiting(12)

      described_class.new.perform
      described_class.new.perform

      expect(ChatflowExecution.where(chatflow: chatflow, conversation: conversation).count).to eq(1)
      expect(conversation.messages.outgoing.pluck(:content)).to eq(['Já te atendo!'])
    end

    it 'waits for the configured minutes' do
      waiting(5)

      described_class.new.perform

      expect(ChatflowExecution.where(chatflow: chatflow).count).to eq(0)
    end
  end
end
