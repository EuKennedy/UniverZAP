# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FollowUpBroadcastService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  # A channel WAHA can actually deliver through. The default inbox factory
  # builds a website widget, which is precisely the case the service refuses.
  before { create(:inbox, account: account, channel: build(:channel_api, account: account)) }

  def lead(phone: '+5511999990000', status: 'open')
    contact = create(:contact, account: account, phone_number: phone)
    create(:ai_lead_opportunity, account: account, ai_assistant: assistant,
                                 contact: contact, status: status)
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

    # A lead marked won bought something and one marked lost was ruled out on
    # purpose. Messaging either is the fastest way to make the radar look like
    # spam to the person receiving it.
    it 'never messages a lead that is already closed' do
      expect { run([lead(status: 'won'), lead(status: 'lost')]) }
        .to raise_error(described_class::NoRecipients)
    end
  end

  describe 'refusals that protect the number' do
    it 'refuses an empty message instead of creating silent conversations' do
      expect { run([lead], message: '   ') }.to raise_error(described_class::BlankMessage)
    end

    # An operator whose agent sits on a website widget would otherwise get a
    # campaign that marks every lead as contacted and reaches nobody.
    it 'refuses when there is no channel that can send WhatsApp' do
      widget_only = create(:account)
      other = create(:ai_assistant, account: widget_only)
      create(:inbox, account: widget_only)
      contact = create(:contact, account: widget_only, phone_number: '+5511988887777')
      target = create(:ai_lead_opportunity, account: widget_only, ai_assistant: other, contact: contact)

      expect do
        described_class.new(assistant: other, opportunity_ids: [target.id], message: 'oi').perform
      end.to raise_error(described_class::NoSendableInbox)
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
