require 'rails_helper'

RSpec.describe TaskPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:creator) { create(:user, account: account, role: :agent) }
  let(:agent)   { create(:user, account: account, role: :agent) }
  let(:assigned_user) { create(:user, account: account, role: :agent) }

  let(:admin_context)    { context_for(administrator) }
  let(:creator_context)  { context_for(creator) }
  let(:agent_context)    { context_for(agent) }
  let(:assigned_context) { context_for(assigned_user) }

  let(:task) { create(:task, account: account, created_by_user: creator) }

  before { task.task_assignees.create!(user: assigned_user) }

  def context_for(user)
    { user: user, account: account, account_user: user.account_users.find_by(account: account) }
  end

  permissions :index?, :show? do
    it 'allows agents' do
      expect(subject).to permit(agent_context, task)
    end

    it 'allows administrators' do
      expect(subject).to permit(admin_context, task)
    end
  end

  permissions :update?, :destroy? do
    it 'allows administrators' do
      expect(subject).to permit(admin_context, task)
    end

    it 'allows the creator' do
      expect(subject).to permit(creator_context, task)
    end

    it 'allows the assigned user' do
      expect(subject).to permit(assigned_context, task)
    end

    it 'denies an unrelated agent' do
      expect(subject).not_to permit(agent_context, task)
    end
  end

  permissions :assign?, :complete? do
    it 'allows administrators' do
      expect(subject).to permit(admin_context, task)
    end

    it 'allows the creator' do
      expect(subject).to permit(creator_context, task)
    end

    it 'denies assigned-only users (must be admin or creator)' do
      expect(subject).not_to permit(assigned_context, task)
    end
  end

  permissions :comment? do
    it 'mirrors show? — any agent' do
      expect(subject).to permit(agent_context, task)
    end
  end
end
