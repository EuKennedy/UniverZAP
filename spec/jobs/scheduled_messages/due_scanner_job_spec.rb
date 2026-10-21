# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledMessages::DueScannerJob do
  include ActiveJob::TestHelper

  let(:conversation) { create(:conversation) }
  let!(:due) { create(:scheduled_message, conversation: conversation, send_at: 1.minute.from_now) }
  let!(:later) { create(:scheduled_message, conversation: conversation, send_at: 2.hours.from_now) }

  it 'reserva só as vencidas e enfileira o envio uma vez' do
    travel_to(5.minutes.from_now) do
      described_class.perform_now
      described_class.perform_now
    end

    expect(due.reload).to be_status_sending
    expect(later.reload).to be_status_scheduled
    expect(enqueued_jobs.count { |job| job[:job] == ScheduledMessages::SendJob }).to eq(1)
  end
end
