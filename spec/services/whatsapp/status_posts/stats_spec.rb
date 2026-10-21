require 'rails_helper'

RSpec.describe Whatsapp::StatusPosts::Stats do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end

  def delivered(status, at: 1.day.ago)
    post = create(:whatsapp_status_post, account: account, status: :publishing, inbox_ids: [inbox.id])
    post.deliveries.create!(inbox: inbox, inbox_name: 'Loja', status: status, sent_at: (at if status == :sent), updated_at: at)
  end

  it 'counts what went out, what failed and the success rate from the deliveries' do
    3.times { delivered(:sent) }
    delivered(:failed)
    delivered(:sent, at: 20.days.ago)
    next_one = create(:whatsapp_status_post, account: account, status: :scheduled, inbox_ids: [inbox.id], scheduled_at: 2.hours.from_now)
    create(:whatsapp_status_post, account: account)
    create(:whatsapp_status_post, account: create(:account))

    stats = described_class.new(account).to_h

    expect(stats).to include(published_7d: 3, failed_7d: 1, scheduled: 1, drafts: 1, success_rate_30d: 80)
    expect(Time.zone.parse(stats[:next_scheduled_at])).to be_within(1.second).of(next_one.scheduled_at)
  end

  it 'has no success rate before anything finished' do
    expect(described_class.new(account).to_h[:success_rate_30d]).to be_nil
  end
end
