require 'rails_helper'

RSpec.describe V2::Reports::DashboardBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, name: 'Ana') }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s, conversion_label: 'agendado', risk_minutes: '30' } }

  before do
    create(:label, account: account, title: 'agendado')
    create(:conversation, account: account, inbox: inbox, assignee: agent, first_reply_created_at: 1.hour.ago,
                          custom_attributes: { 'origem_lead' => 'anuncio_facebook', 'anuncio_id' => '100', 'anuncio_titulo' => 'Progressiva' })
    create(:conversation, account: account, inbox: inbox, awaiting_reply: true)
      .update_columns(waiting_since: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
  end

  it 'composes the funnel, the queue and the agents blocks' do
    result = described_class.new(account: account, params: params).build

    expect(result[:funnel][:by_ad].first).to include(ad_id: '100', leads: 1, replied: 1)
    expect(result[:funnel][:by_agent].first).to include(agent_id: agent.id, title: 'Ana', leads: 1)
    expect(result[:funnel][:by_customer].map { |row| row[:customer] }).to eq(%w[new recurring])
    expect(result[:queue]).to include(waiting: 1, at_risk: 1)
    expect(result[:agents].map { |row| row[:agent_id] }).to contain_exactly(agent.id, nil)
    expect(result[:risk_minutes]).to eq(30)
  end
end
