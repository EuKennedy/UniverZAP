require 'rails_helper'

RSpec.describe V2::Reports::AgentPerformanceBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:bia) { create(:user, account: account, name: 'Bia') }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s, conversion_label: 'agendado', risk_minutes: '30' } }

  def conversation(waiting_since: :keep, **attrs)
    create(:conversation, account: account, inbox: inbox, **attrs).tap do |record|
      record.update_columns(waiting_since: waiting_since) unless waiting_since == :keep # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    create(:label, account: account, title: 'agendado')
    conversation(assignee: ana, created_at: 2.days.ago, first_reply_created_at: 2.days.ago + 4.minutes).add_labels(['agendado'])
    conversation(assignee: ana, created_at: 2.days.ago, first_reply_created_at: 2.days.ago + 8.minutes, status: :resolved)
    conversation(assignee: ana, created_at: 1.day.ago, waiting_since: 50.minutes.ago, awaiting_reply: true)
    conversation(assignee: bia, created_at: 1.day.ago, first_reply_created_at: 1.day.ago + 20.minutes)
    conversation(created_at: 1.day.ago, waiting_since: 50.minutes.ago, awaiting_reply: true) # sem atendente
    conversation(assignee: ana, created_at: 20.days.ago, first_reply_created_at: 20.days.ago + 1.minute) # fora do período
  end

  it 'builds one row per agent with period and live metrics' do
    rows = described_class.new(account: account, params: params).build

    ana_row = rows.find { |row| row[:agent_id] == ana.id }
    expect(ana_row).to include(name: 'Ana', assigned: 3, replied: 2, resolved: 1, converted: 1, waiting: 1, at_risk: 1)
    expect(ana_row[:median_first_response_seconds]).to eq(360)

    bia_row = rows.find { |row| row[:agent_id] == bia.id }
    expect(bia_row).to include(name: 'Bia', assigned: 1, replied: 1, resolved: 0, converted: 0, waiting: 0, at_risk: 0)
    expect(bia_row[:median_first_response_seconds]).to eq(1200)
  end

  it 'adds an unassigned row when conversations have no assignee' do
    rows = described_class.new(account: account, params: params).build

    unassigned = rows.find { |row| row[:agent_id].nil? }
    expect(unassigned).to include(assigned: 1, waiting: 1, at_risk: 1)
  end

  it 'sorts by assigned conversations, most first' do
    rows = described_class.new(account: account, params: params).build

    expect(rows.map { |row| row[:assigned] }).to eq(rows.map { |row| row[:assigned] }.sort.reverse)
    expect(rows.first[:agent_id]).to eq(ana.id)
  end

  it 'reports converted as nil without a conversion label' do
    rows = described_class.new(account: account, params: params.except(:conversion_label)).build

    expect(rows.first[:converted]).to be_nil
  end
end
