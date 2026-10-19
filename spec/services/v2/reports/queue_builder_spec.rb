require 'rails_helper'

RSpec.describe V2::Reports::QueueBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s, risk_minutes: '30' } }

  # Conversation#ensure_waiting_since stamps created_at on create, so the
  # waiting clock is set afterwards, the way an incoming message would.
  def conversation(waiting_since: :keep, **attrs)
    create(:conversation, account: account, inbox: inbox, contact: contact, **attrs).tap do |record|
      record.update_columns(waiting_since: waiting_since) unless waiting_since == :keep # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    # Five replied in the period: 2, 10, 20, 60 and 60 minutes -> median 20 min.
    conversation(created_at: 2.days.ago, first_reply_created_at: 2.days.ago + 2.minutes)
    conversation(created_at: 2.days.ago, first_reply_created_at: 2.days.ago + 10.minutes)
    conversation(created_at: 1.day.ago, first_reply_created_at: 1.day.ago + 20.minutes)
    # Replied before, but the contact has the last word for 2 hours: at risk, not waiting.
    conversation(created_at: 4.hours.ago, first_reply_created_at: 3.hours.ago, waiting_since: 2.hours.ago, awaiting_reply: true)
    # Agent has the last word: not at risk.
    conversation(created_at: 4.hours.ago, first_reply_created_at: 3.hours.ago, waiting_since: nil, awaiting_reply: false)
    # Waiting (never replied) and at risk: the contact wrote 45 minutes ago.
    conversation(assignee: agent, waiting_since: 45.minutes.ago, awaiting_reply: true)
    # Waiting but not yet at risk (10 minutes).
    conversation(waiting_since: 10.minutes.ago, awaiting_reply: true)
    # Resolved conversations are out of the queue.
    conversation(status: :resolved, waiting_since: 3.hours.ago, awaiting_reply: true)
  end

  it 'counts the live queue and the median first response time of the period' do
    result = described_class.new(account: account, params: params).build

    expect(result).to include(open: 7, waiting: 2, at_risk: 2, created: 8, replied: 5)
    expect(result[:median_first_response_seconds]).to eq(1200)
  end

  it 'lists the at-risk conversations oldest first with contact and assignee' do
    result = described_class.new(account: account, params: params).build

    rows = result[:at_risk_conversations]
    expect(rows.length).to eq(2)
    expect(rows.first).to include(contact: 'Maria', assignee: nil)
    expect(rows.last).to include(contact: 'Maria', assignee: agent.name)
    expect(rows.first[:waiting_since]).to be < rows.last[:waiting_since]
  end

  it 'honours the risk threshold' do
    result = described_class.new(account: account, params: params.merge(risk_minutes: '5')).build

    expect(result[:at_risk]).to eq(3)
  end

  it 'reports a nil median when nothing was replied in the period' do
    result = described_class.new(account: account, params: params.merge(since: 1.hour.ago.to_i.to_s)).build

    expect(result[:median_first_response_seconds]).to be_nil
  end
end
