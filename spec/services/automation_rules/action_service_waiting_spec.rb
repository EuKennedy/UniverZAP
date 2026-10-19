require 'rails_helper'

RSpec.describe AutomationRules::ActionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:busy) { create(:user, account: account, role: :agent, availability: :online) }
  let(:idle) { create(:user, account: account, role: :agent, availability: :online) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: busy) }

  def rule_with(action_name, params = [])
    create(:automation_rule, account: account, event_name: 'conversation_waiting',
                             actions: [{ 'action_name' => action_name, 'action_params' => params }])
  end

  describe 'assign_least_busy' do
    let(:policy) { create(:assignment_policy, account: account, assignment_order: :least_busy, require_online: false) }

    before do
      create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
      create(:inbox_member, inbox: inbox, user: busy)
      create(:inbox_member, inbox: inbox, user: idle)
      create_list(:conversation, 2, account: account, inbox: inbox, assignee: busy, status: :open)
      rate_limiter = instance_double(AutoAssignment::RateLimiter, within_limit?: true, track_assignment: nil)
      allow(AutoAssignment::RateLimiter).to receive(:new).and_return(rate_limiter)
    end

    it 'hands the conversation to another member with fewer open conversations' do
      described_class.new(rule_with('assign_least_busy'), account, conversation).perform

      expect(conversation.reload.assignee).to eq(idle)
    end

    it 'never gives it back to the agent who is not answering' do
      inbox.inbox_members.find_by(user: idle).destroy!

      described_class.new(rule_with('assign_least_busy'), account, conversation).perform

      expect(conversation.reload.assignee).to eq(busy)
    end
  end

  describe 'notify_team' do
    let(:team) { create(:team, account: account, name: 'gerencia') }
    let(:manager) { create(:user, account: account, role: :administrator) }

    before { create(:team_member, team: team, user: manager) }

    it 'leaves a private note mentioning the team so its members get notified' do
      rule = rule_with('notify_team', [{ 'team_ids' => [team.id], 'message' => 'Cliente esperando há 15 min' }])

      described_class.new(rule, account, conversation).perform

      note = conversation.messages.where(private: true).last
      expect(note.content).to include("(mention://team/#{team.id}/gerencia)")
      expect(note.content).to include('Cliente esperando há 15 min')
      expect(note.content_attributes['automation_rule_id']).to eq(rule.id)
    end
  end

  describe 'start_chatflow' do
    let(:chatflow) { Chatflow.create!(account: account, name: 'Resgate', inbox: inbox, status: :active) }

    it 'starts the chosen flow on the conversation' do
      allow(Chatflow::EngineService).to receive(:force_start)

      described_class.new(rule_with('start_chatflow', [chatflow.id]), account, conversation).perform

      expect(Chatflow::EngineService).to have_received(:force_start).with(chatflow, conversation)
    end

    it 'ignores a flow from another account' do
      other = Chatflow.create!(account: create(:account), name: 'Alheio', status: :active)
      allow(Chatflow::EngineService).to receive(:force_start)

      described_class.new(rule_with('start_chatflow', [other.id]), account, conversation).perform

      expect(Chatflow::EngineService).not_to have_received(:force_start)
    end
  end
end
