require 'rails_helper'

RSpec.describe V2::Reports::AdLeadsBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s, conversion_label: 'agendado' } }

  def lead(ad_id:, title:, **attrs)
    create(:conversation, account: account, inbox: inbox,
                          custom_attributes: { 'origem_lead' => 'anuncio_facebook', 'anuncio_id' => ad_id, 'anuncio_titulo' => title,
                                               'anuncio_url' => "https://fb.me/#{ad_id}" }, **attrs)
  end

  before do
    create(:label, account: account, title: 'agendado')
    lead(ad_id: '100', title: 'Progressiva')
    lead(ad_id: '100', title: 'Progressiva', first_reply_created_at: 1.hour.ago).add_labels(['agendado'])
    lead(ad_id: '100', title: 'Progressiva', status: :resolved)
    lead(ad_id: '200', title: 'Manicure')
    create(:conversation, account: account, inbox: inbox) # sem anúncio
    lead(ad_id: '300', title: 'Antigo', created_at: 30.days.ago)
  end

  it 'groups leads by ad with replied, resolved and converted counts inside the period' do
    rows = described_class.new(account: account, params: params).build

    expect(rows.map { |r| r[:ad_id] }).to eq(%w[100 200])
    first = rows.first
    expect(first).to include(ad_id: '100', title: 'Progressiva', url: 'https://fb.me/100', leads: 3, replied: 1, resolved: 1, converted: 1)
    expect(rows.last).to include(ad_id: '200', leads: 1, converted: 0)
  end

  it 'reports converted as nil when no conversion label is given' do
    rows = described_class.new(account: account, params: params.except(:conversion_label)).build

    expect(rows.first[:converted]).to be_nil
  end

  it 'groups by assignee when asked, naming the agent' do
    lead(ad_id: '400', title: 'Escova', assignee: agent, first_reply_created_at: 1.hour.ago).add_labels(['agendado'])

    rows = described_class.new(account: account, params: params.merge(group_by: 'agent')).build

    agent_row = rows.find { |row| row[:agent_id] == agent.id }
    expect(agent_row).to include(title: agent.name, leads: 1, replied: 1, converted: 1)
    expect(rows.find { |row| row[:agent_id].nil? }).to include(leads: 4, converted: 1)
    expect(rows.first[:leads]).to eq(4)
  end

  it 'splits the leads into new and returning customers when asked, new first' do
    create(:label, account: account, title: 'cliente-recorrente')
    lead(ad_id: '200', title: 'Manicure', first_reply_created_at: 1.hour.ago).add_labels(%w[cliente-recorrente agendado])

    rows = described_class.new(account: account, params: params.merge(group_by: 'customer')).build

    expect(rows).to eq([
                         { customer: 'new', leads: 4, replied: 1, resolved: 1, converted: 1 },
                         { customer: 'recurring', leads: 1, replied: 1, resolved: 0, converted: 1 }
                       ])
  end

  it 'shows both customer rows even when nobody is returning' do
    rows = described_class.new(account: account, params: params.merge(group_by: 'customer')).build

    expect(rows.map { |row| row[:customer] }).to eq(%w[new recurring])
    expect(rows.last).to include(leads: 0, replied: 0, resolved: 0, converted: 0)
  end

  it 'counts returning customers by the e-commerce label on an e-commerce account' do
    account.update!(custom_attributes: { 'vertical_template' => 'ecommerce' })
    create(:label, account: account, title: 'comprou-novamente')
    lead(ad_id: '200', title: 'Kit', first_reply_created_at: 1.hour.ago).add_labels(%w[comprou-novamente])

    rows = described_class.new(account: account, params: params.merge(group_by: 'customer')).build

    expect(rows.pluck(:customer, :leads)).to eq([['new', 4], ['recurring', 1]])
  end
end
