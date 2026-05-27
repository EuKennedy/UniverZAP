# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation do
  describe '#toggle_pin!' do
    let(:conversation) { create(:conversation) }

    it 'pins an unpinned conversation by stamping pinned_at' do
      expect { conversation.toggle_pin! }.to change(conversation, :pinned_at).from(nil)
      expect(conversation.pinned_at).to be_within(2.seconds).of(Time.current)
    end

    it 'unpins a pinned conversation by clearing pinned_at' do
      conversation.update!(pinned_at: 1.hour.ago)
      expect { conversation.toggle_pin! }.to change(conversation, :pinned_at).to(nil)
    end
  end

  describe 'sort respecting pinned_at' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let!(:newer) { create(:conversation, account: account, inbox: inbox, last_activity_at: 1.minute.ago) }
    let!(:older) { create(:conversation, account: account, inbox: inbox, last_activity_at: 2.hours.ago) }

    it 'floats pinned conversations above unpinned peers regardless of last activity' do
      older.update!(pinned_at: Time.current)
      sorted = Conversation.sort_on_last_activity_at(:desc).where(account_id: account.id, inbox_id: inbox.id)
      expect(sorted.first).to eq(older)
      expect(sorted.last).to eq(newer)
    end
  end
end
