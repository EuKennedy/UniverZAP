# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InboxMember do
  include ActiveJob::TestHelper

  describe 'assignment_capacity' do
    let(:inbox) { create(:inbox) }

    it 'is unlimited when blank' do
      expect(build(:inbox_member, inbox: inbox, assignment_capacity: nil)).to be_valid
    end

    it 'accepts a positive number of open conversations' do
      expect(build(:inbox_member, inbox: inbox, assignment_capacity: 3)).to be_valid
    end

    it 'rejects zero or negative capacity' do
      expect(build(:inbox_member, inbox: inbox, assignment_capacity: 0)).not_to be_valid
      expect(build(:inbox_member, inbox: inbox, assignment_capacity: -1)).not_to be_valid
    end
  end

  describe '#DestroyAssociationAsyncJob' do
    let(:inbox_member) { create(:inbox_member) }

    # ref: https://github.com/chatwoot/chatwoot/issues/4616
    context 'when parent inbox is destroyed' do
      it 'enques and processes DestroyAssociationAsyncJob' do
        perform_enqueued_jobs do
          inbox_member.inbox.destroy!
        end
        expect { inbox_member.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
