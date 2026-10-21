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

  # A promoção de terça sai toda terça sem ninguém agendar de novo.
  it 'schedules the next occurrence of a weekly status from the agreed time' do
    weekly = create(:whatsapp_status_post, account: account, status: :scheduled, inbox_ids: [inbox.id],
                                           scheduled_at: 10.minutes.from_now, recurrence: 'weekly')

    travel 15.minutes do
      described_class.perform_now
    end

    following = account.whatsapp_status_posts.status_scheduled.sole
    expect(following.scheduled_at).to eq(weekly.scheduled_at + 1.week)
    expect(following).to have_attributes(body: weekly.body, recurrence: 'weekly', inbox_ids: [inbox.id])
    expect(weekly.reload).to be_status_publishing
  end
end
