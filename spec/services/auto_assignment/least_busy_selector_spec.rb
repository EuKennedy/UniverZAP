require 'rails_helper'

RSpec.describe AutoAssignment::LeastBusySelector do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:busy_agent) { create(:user, account: account, role: :agent) }
  let(:idle_agent) { create(:user, account: account, role: :agent) }
  let(:busy_member) { create(:inbox_member, inbox: inbox, user: busy_agent) }
  let(:idle_member) { create(:inbox_member, inbox: inbox, user: idle_agent) }
  # The `before` conversations run the assignment handler, which caches an
  # empty inbox_members on this object; the round robin needs a fresh inbox.
  let(:selector) { described_class.new(inbox: inbox.reload) }

  before do
    create_list(:conversation, 2, inbox: inbox, assignee: busy_agent, status: :open)
  end

  it 'returns nil when there is nobody to pick from' do
    expect(selector.select_agent([])).to be_nil
  end

  it 'picks the agent with the fewest open conversations in the inbox' do
    expect(selector.select_agent([busy_member, idle_member])).to eq(idle_agent)
  end

  it 'ignores resolved conversations when counting load' do
    create(:conversation, inbox: inbox, assignee: idle_agent, status: :resolved)
    create(:conversation, inbox: inbox, assignee: idle_agent, status: :resolved)
    create(:conversation, inbox: inbox, assignee: idle_agent, status: :resolved)

    expect(selector.select_agent([busy_member, idle_member])).to eq(idle_agent)
  end

  it 'breaks ties with the inbox round robin' do
    create_list(:conversation, 2, inbox: inbox, assignee: idle_agent, status: :open)
    round_robin = instance_double(AutoAssignment::RoundRobinSelector)
    allow(AutoAssignment::RoundRobinSelector).to receive(:new).with(inbox: inbox).and_return(round_robin)
    allow(round_robin).to receive(:select_agent).with([busy_member, idle_member]).and_return(busy_agent)

    expect(selector.select_agent([busy_member, idle_member])).to eq(busy_agent)
  end
end
