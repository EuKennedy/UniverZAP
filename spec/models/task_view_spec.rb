require 'rails_helper'

RSpec.describe TaskView, type: :model do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  it 'persists with required attributes' do
    view = build(:task_view, account: account, user: user)
    expect(view).to be_valid
  end

  it 'enforces presence of name' do
    view = build(:task_view, account: account, user: user, name: nil)
    expect(view).not_to be_valid
  end

  it 'permits a NULL user (shared view)' do
    view = build(:task_view, account: account, user: nil)
    expect(view).to be_valid
  end

  describe '#default_unique_per_owner' do
    it 'allows one default per user' do
      create(:task_view, account: account, user: user, is_default: true)
      duplicate = build(:task_view, account: account, user: user, is_default: true)
      expect(duplicate).not_to be_valid
    end

    it 'does not collide across users' do
      other = create(:user, account: account)
      create(:task_view, account: account, user: user, is_default: true)
      sibling = build(:task_view, account: account, user: other, is_default: true)
      expect(sibling).to be_valid
    end
  end

  describe '.visible_to' do
    it 'returns own + shared views' do
      mine = create(:task_view, account: account, user: user)
      shared = create(:task_view, account: account, user: nil)
      other_user = create(:user, account: account)
      create(:task_view, account: account, user: other_user)
      visible_ids = described_class.visible_to(user.id).pluck(:id)
      expect(visible_ids).to include(mine.id, shared.id)
    end
  end

  describe '#push_event_data' do
    it 'serializes a stable payload' do
      view = create(:task_view, account: account, user: user, name: 'foo', is_default: true)
      payload = view.push_event_data
      expect(payload).to include(:id, :name, :filters, :is_default, :shared)
      expect(payload[:shared]).to be(false)
      expect(payload[:is_default]).to be(true)
    end
  end
end
