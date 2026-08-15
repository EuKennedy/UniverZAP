# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Belezaki::BookingRecorder do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:connection) do
    Ai::Belezaki::Connection.create!(
      ai_assistant: assistant, account: account, external_id: 'salon-1', status: 'active'
    )
  end
  let(:recorder) { described_class.new(connection: connection, conversation: conversation) }

  let(:appointment) do
    { 'id' => 'apt-77', 'start' => '2026-08-20T14:00:00-03:00', 'service' => 'Escova',
      'professional' => 'Marcela', 'price_cents' => 9_000 }
  end

  def events
    Ai::RevenueEvent.where(account_id: account.id)
  end

  describe 'a confirmed booking' do
    it 'writes it down with the price the salon quoted' do
      recorder.booked(appointment)

      expect(events.count).to eq(1)
      expect(events.first.amount_brl).to eq(90.0)
    end

    it 'attributes it to the agent, the conversation and the customer' do
      recorder.booked(appointment)

      expect(events.first).to have_attributes(
        ai_assistant_id: assistant.id, conversation_id: conversation.id,
        contact_id: contact.id, source: 'agendamento', recorded_by: 'agent'
      )
    end

    # The row is keyed on the salon's own appointment id, which is what the
    # unique index on (account_id, external_ref) was built for. A customer
    # confirming twice, or a turn being replayed, must not sell the same slot
    # twice on the report.
    it 'stays one row however many times the same appointment is confirmed' do
      3.times { recorder.booked(appointment) }

      expect(events.count).to eq(1)
    end

    it 'keeps the service and the professional, for the row to be recognisable' do
      recorder.booked(appointment)

      expect(events.first.metadata).to include('service' => 'Escova', 'professional' => 'Marcela')
    end

    it 'ignores a response that carried no appointment' do
      recorder.booked(nil)
      recorder.booked({})

      expect(events).to be_empty
    end
  end

  describe 'the comanda' do
    before { recorder.booked(appointment) }

    # The till is what happened; the price quoted at booking was a promise.
    it 'corrects the amount to what was actually billed' do
      recorder.billed('apt-77', 12_500)

      expect(events.count).to eq(1)
      expect(events.first.amount_brl).to eq(125.0)
    end

    # A comanda that answers without a total must not silently zero a real sale.
    it 'leaves the amount alone when the till gave none' do
      recorder.billed('apt-77', nil)

      expect(events.first.amount_brl).to eq(90.0)
    end

    # The after-hours figure is the strongest argument the module has, and it
    # reads occurred_at. A comanda opened the next morning must not move a sale
    # out of the night it was taken in.
    it 'does not move the sale to the moment the till opened' do
      booked_at = events.first.occurred_at

      travel_to(12.hours.from_now) { recorder.billed('apt-77', 12_500) }

      expect(events.first.occurred_at).to be_within(1.second).of(booked_at)
    end
  end

  # A cancelled appointment was never money, and leaving it behind inflates the
  # one figure an operator repeats to somebody else.
  describe 'a cancellation' do
    it 'takes the sale back off the report' do
      recorder.booked(appointment)

      recorder.cancelled('apt-77')

      expect(events).to be_empty
    end

    it 'says nothing about an appointment it never recorded' do
      expect { recorder.cancelled('apt-never') }.not_to raise_error
    end
  end

  # The playground has no connection, and a sandbox turn must never write a sale.
  describe 'without a connection' do
    let(:recorder) { described_class.new(connection: nil) }

    it 'writes nothing' do
      recorder.booked(appointment)
      recorder.billed('apt-77', 9_000)

      expect(Ai::RevenueEvent.count).to be_zero
    end
  end

  # The customer has already been told they have a time. Our bookkeeping failing
  # is our problem, and it must never turn a successful booking into an error.
  it 'never raises when the write fails' do
    allow(Ai::RevenueEvent).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'boom')

    expect { recorder.booked(appointment) }.not_to raise_error
  end
end
