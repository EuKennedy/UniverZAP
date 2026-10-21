require 'rails_helper'

RSpec.describe WhatsappStatusCampaign do
  let(:account) { create(:account) }

  it 'can be saved as a draft with nothing but a name' do
    expect(build(:whatsapp_status_campaign, account: account)).to be_valid
  end

  # Ativar sem data, conexão ou passo seria uma campanha que nunca sai.
  it 'needs a start date, connections and steps to be activated' do
    campaign = create(:whatsapp_status_campaign, account: account)
    campaign.status = :active

    expect(campaign).not_to be_valid
    expect(campaign.errors.attribute_names).to include(:starts_on, :steps, :inbox_ids)
  end

  it 'refuses a folder of another account' do
    campaign = build(:whatsapp_status_campaign, account: account, folder: create(:whatsapp_status_folder))

    expect(campaign).not_to be_valid
  end

  it 'refuses an unknown time zone' do
    expect(build(:whatsapp_status_campaign, account: account, time_zone: 'Lua/Base')).not_to be_valid
  end
end
