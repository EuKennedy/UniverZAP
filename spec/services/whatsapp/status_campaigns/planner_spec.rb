require 'rails_helper'

RSpec.describe Whatsapp::StatusCampaigns::Planner do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  # Segunda, 26/10/2026, 8h em Brasília.
  let(:now) { zone.local(2026, 10, 26, 8) }
  let(:campaign) do
    create(:whatsapp_status_campaign, account: account, inbox_ids: [inbox.id], starts_on: Date.new(2026, 10, 26))
  end

  def add_step(**attributes)
    create(:whatsapp_status_campaign_step, campaign: campaign, **attributes)
  end

  def activate!
    campaign.reload.update!(status: :active)
  end

  it 'schedules each step on its day and time, in the campaign time zone' do
    add_step(day_offset: 0, time_of_day: '09:00')
    add_step(day_offset: 2, time_of_day: '18:30', body: 'Última chamada')
    activate!

    travel_to(now) { described_class.new(campaign).plan! }

    posts = campaign.posts.order(:scheduled_at)
    expect(posts.map { |post| post.scheduled_at.in_time_zone(zone).strftime('%d/%m %H:%M') }).to eq(['26/10 09:00', '28/10 18:30'])
    expect(posts.map(&:status).uniq).to eq(['scheduled'])
    expect(posts.last).to have_attributes(body: 'Última chamada', inbox_ids: [inbox.id], campaign_step: campaign.steps.last)
  end

  # O status some em 24h: repostar mantém a promoção visível a semana toda.
  it 'reposts a step the configured number of times' do
    add_step(time_of_day: '09:00', repost_count: 2, repost_interval_hours: 24)
    activate!

    travel_to(now) { described_class.new(campaign).plan! }

    expect(campaign.posts.order(:scheduled_at).map { |post| post.scheduled_at.in_time_zone(zone).day }).to eq([26, 27, 28])
  end

  it 'restarts the flow every cycle and only fills the next 14 days' do
    add_step(time_of_day: '09:00')
    campaign.update!(cycle_days: 7)
    activate!

    travel_to(now) { described_class.new(campaign).plan! }

    expect(campaign.posts.order(:scheduled_at).map { |post| post.scheduled_at.in_time_zone(zone).to_date.to_s })
      .to eq(%w[2026-10-26 2026-11-02])

    # A janela anda com o tempo: no dia seguinte, o ciclo de 09/11 já entra.
    travel_to(now + 1.day) { described_class.new(campaign).plan! }
    expect(campaign.posts.count).to eq(3)
  end

  it 'never schedules the same occurrence twice' do
    add_step(time_of_day: '09:00', repost_count: 1)
    activate!

    travel_to(now) { 2.times { described_class.new(campaign).plan! } }

    expect(campaign.posts.count).to eq(2)
  end

  it 'skips what is already in the past and stops at the end date' do
    add_step(time_of_day: '07:00')
    campaign.update!(cycle_days: 7, ends_on: Date.new(2026, 11, 3))
    activate!

    travel_to(now) { described_class.new(campaign).plan! }

    expect(campaign.posts.map { |post| post.scheduled_at.in_time_zone(zone).to_date.to_s }).to eq(%w[2026-11-02])
  end

  it 'finishes a one-off campaign once nothing is left to go out' do
    add_step(time_of_day: '07:00')
    activate!

    travel_to(now) { described_class.new(campaign).plan! }

    expect(campaign.reload).to be_status_finished
  end

  it 'copies the media of the step to the post' do
    blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'a.png',
                                                  content_type: 'image/png')
    step = build(:whatsapp_status_campaign_step, campaign: campaign, kind: 'image', body: 'Chegou')
    step.media = blob
    step.save!
    activate!

    travel_to(now) { described_class.new(campaign).plan! }

    expect(campaign.posts.sole.media.blob).to eq(blob)
  end
end
