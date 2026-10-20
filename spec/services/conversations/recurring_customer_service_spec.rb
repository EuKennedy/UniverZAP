require 'rails_helper'

RSpec.describe Conversations::RecurringCustomerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }

  def conversation(**attrs)
    create(:conversation, account: account, inbox: inbox, contact: contact, **attrs)
  end

  # What ReportingEventListener leaves behind when a conversation is resolved.
  def resolved_event(conversation, at:)
    create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: conversation, user: nil,
                             event_start_time: conversation.created_at, event_end_time: at)
  end

  def contact_message(conversation, at: Time.current, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi', created_at: at, **attrs)
  end

  before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

  describe '.recurring?' do
    it 'is false for the first conversation of a contact' do
      expect(described_class.recurring?(conversation)).to be false
    end

    it 'is false while the previous conversation is still open' do
      conversation
      expect(described_class.recurring?(conversation)).to be false
    end

    it 'is true once a previous conversation was resolved' do
      conversation(status: :resolved)
      expect(described_class.recurring?(conversation)).to be true
    end

    it 'is true when a previous, reopened conversation carries a label that closes conversations' do
      create(:label, account: account, title: 'cancelado', closes_conversation: true)
      previous = conversation
      previous.add_labels(['cancelado'])
      previous.update!(status: :open)

      expect(described_class.recurring?(conversation)).to be true
    end

    it 'ignores labels that do not close conversations and other contacts' do
      create(:label, account: account, title: 'triagem')
      conversation.add_labels(['triagem'])
      create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account), status: :resolved)

      expect(described_class.recurring?(conversation)).to be false
    end

    context 'with a single conversation per contact, reopened on every return' do
      let(:current) { conversation(created_at: 3.days.ago) }

      it 'is true when the conversation was resolved and the contact wrote again' do
        contact_message(current, at: 3.days.ago)
        resolved_event(current, at: 2.days.ago)
        contact_message(current, at: 1.day.ago)

        expect(current.reload).to be_open
        expect(described_class.recurring?(current)).to be true
      end

      it 'is false when the conversation was resolved once and nobody wrote since' do
        contact_message(current, at: 3.days.ago)
        current.resolved!
        resolved_event(current, at: 2.days.ago)

        expect(described_class.recurring?(current)).to be false
      end

      it 'is false when the conversation was never resolved' do
        contact_message(current, at: 3.days.ago)
        contact_message(current, at: 1.day.ago)

        expect(described_class.recurring?(current)).to be false
      end

      it 'ignores agent replies and private notes sent after the resolution' do
        contact_message(current, at: 3.days.ago)
        resolved_event(current, at: 2.days.ago)
        create(:message, account: account, inbox: inbox, conversation: current, message_type: :outgoing, content: 'oi?', created_at: 1.day.ago)
        contact_message(current, at: 1.day.ago, private: true)

        expect(described_class.recurring?(current)).to be false
      end
    end
  end

  describe '#perform' do
    it 'does nothing for a first-time customer' do
      current = conversation

      described_class.new(current).perform

      expect(current.reload.label_list).to eq([])
      expect(contact.reload.custom_attributes).not_to have_key('recorrente')
      expect(account.labels.find_by(title: 'cliente-recorrente')).to be_nil
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_RECURRING_CUSTOMER, anything, anything)
    end

    context 'when the contact already had a conversation that ended' do
      before { conversation(status: :resolved) }

      let(:current) { conversation }

      it 'labels the conversation, stamps the contact and creates the label and the definition' do
        described_class.new(current).perform

        expect(current.reload.label_list).to eq(['cliente-recorrente'])
        expect(contact.reload.custom_attributes['recorrente']).to be true
        expect(account.labels.find_by(title: 'cliente-recorrente')).to have_attributes(color: '#94A3B8', show_on_sidebar: true)
        expect(account.custom_attribute_definitions.find_by(attribute_key: 'recorrente', attribute_model: 'contact_attribute'))
          .to have_attributes(attribute_display_type: 'checkbox', attribute_display_name: 'Returning customer')
      end

      it 'dispatches conversation.recurring_customer once per conversation' do
        described_class.new(current).perform
        described_class.new(current.reload).perform

        expect(current.reload.label_list).to eq(['cliente-recorrente'])
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          Events::Types::CONVERSATION_RECURRING_CUSTOMER, kind_of(Time), hash_including(conversation: current, contact: contact)
        ).once
      end

      it 'labels and stamps without firing the event when silent (backfill)' do
        described_class.new(current, silent: true).perform

        expect(current.reload.label_list).to eq(['cliente-recorrente'])
        expect(contact.reload.custom_attributes['recorrente']).to be true
        expect(Rails.configuration.dispatcher)
          .not_to have_received(:dispatch).with(Events::Types::CONVERSATION_RECURRING_CUSTOMER, anything, anything)
      end
    end

    context 'when the same conversation was resolved and the contact came back' do
      let(:current) { conversation(created_at: 3.days.ago) }

      before do
        contact_message(current, at: 3.days.ago)
        resolved_event(current, at: 2.days.ago)
        contact_message(current, at: 1.day.ago)
      end

      it 'labels the conversation, stamps the contact and fires the event once for the cycle' do
        described_class.new(current).perform
        contact_message(current)
        described_class.new(current.reload).perform

        expect(current.reload.label_list).to eq(['cliente-recorrente'])
        expect(contact.reload.custom_attributes['recorrente']).to be true
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          Events::Types::CONVERSATION_RECURRING_CUSTOMER, kind_of(Time), hash_including(conversation: current, contact: contact)
        ).once
      end

      it 'does not fire when another job labelled the conversation in the meantime' do
        loaded_before = Conversation.find(current.id)
        expect(loaded_before.label_list).to eq([])
        current.add_labels(['cliente-recorrente'])

        described_class.new(loaded_before).perform

        expect(Rails.configuration.dispatcher)
          .not_to have_received(:dispatch).with(Events::Types::CONVERSATION_RECURRING_CUSTOMER, anything, anything)
      end
    end
  end

  describe '#stamp_contact' do
    it 'stamps once and reports whether it wrote' do
      service = described_class.new(conversation)

      expect(service.stamp_contact).to be true
      expect(service.stamp_contact).to be false
      expect(contact.reload.custom_attributes['recorrente']).to be true
    end
  end
end
