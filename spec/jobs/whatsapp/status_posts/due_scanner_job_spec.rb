require 'rails_helper'

RSpec.describe Whatsapp::StatusPosts::DueScannerJob do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end

  it 'claims due posts once and enqueues their publication' do
    due = create(:whatsapp_status_post, account: account, status: :scheduled, inbox_ids: [inbox.id], scheduled_at: 10.minutes.from_now)
    later = create(:whatsapp_status_post, account: account, status: :scheduled, inbox_ids: [inbox.id], scheduled_at: 2.hours.from_now)

    travel 15.minutes do
      expect { described_class.perform_now }.to have_enqueued_job(Whatsapp::StatusPosts::PublishJob).with(due.id).exactly(:once)
      expect { described_class.perform_now }.not_to have_enqueued_job(Whatsapp::StatusPosts::PublishJob)
    end

    expect(due.reload).to be_status_publishing
    expect(later.reload).to be_status_scheduled
  end
end
