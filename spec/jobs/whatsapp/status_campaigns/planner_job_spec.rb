require 'rails_helper'

RSpec.describe Whatsapp::StatusCampaigns::PlannerJob do
  it 'plans only the active campaigns' do
    account = create(:account)
    inbox = create(:channel_api, account: account,
                                 additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
    active = create(:whatsapp_status_campaign, account: account, inbox_ids: [inbox.id], starts_on: 1.day.from_now.to_date)
    create(:whatsapp_status_campaign_step, campaign: active)
    active.update!(status: :active)
    draft = create(:whatsapp_status_campaign, account: account, inbox_ids: [inbox.id], starts_on: 1.day.from_now.to_date)
    create(:whatsapp_status_campaign_step, campaign: draft)

    described_class.perform_now

    expect(active.posts.count).to eq(1)
    expect(draft.posts.count).to eq(0)
  end
end
