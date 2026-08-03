# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FollowUpBroadcastService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let!(:inbox) { create(:inbox, account: account) }

  def lead(phone: '+5511999990000')
    contact = create(:contact, account: account, phone_number: phone)
    create(:ai_lead_opportunity, account: account, ai_assistant: assistant, contact: contact)
  end

  def run(leads, message: 'Ainda tem interesse?')
    described_class.new(assistant: assistant, opportunity_ids: leads.map(&:id), message: message).perform
  end

  describe 'it reuses the dispatcher that already knows how not to get banned' do
    it 'creates a broadcast instead of sending anything itself' do
      expect { run([lead]) }.to change { account.broadcasts.count }.by(1)
    end

    it 'hands the dispatch to the throttled job' do
      allow(Broadcasts::DispatchJob).to receive(:perform_later)

      broadcast = run([lead])

      expect(Broadcasts::DispatchJob).to have_received(:perform_later).with(broadcast.id)
    end

    # A follow-up goes to people who did NOT buy, so a burst of them is exactly
    # the pattern WhatsApp reads as spam.
    it 'is more conservative than the default campaign throttle' do
      broadcast = run([lead])

      expect(broadcast.batch_max).to be <= Broadcast.new.batch_max
      expect(broadcast.delay_min).to be >= Broadcast.new.delay_min
    end
  end

  describe 'recipients' do
    it 'drops a lead with no phone number instead of failing inside the dispatcher' do
      reachable = lead
      lead(phone: nil)

      broadcast = run(Ai::LeadOpportunity.all.to_a)

      expect(broadcast.audience['contact_ids']).to eq([reachable.contact_id])
    end

    it 'refuses a selection nobody can be reached in' do
      expect { run([lead(phone: nil)]) }.to raise_error(described_class::NoRecipients)
    end
  end

  describe 'status' do
    # `followed`, not `won`: the message went out, the sale did not happen yet.
    # Conflating the two is how a radar starts reporting revenue that never came.
    it 'marks the leads as followed, never as won' do
      target = lead

      run([target])

      expect(target.reload.status).to eq('followed')
      expect(target.followed_up_at).to be_present
    end
  end
end
