# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Reports::AccountOverview do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account, name: 'Marina') }
  let(:report) { described_class.new(account: account, days: 30).perform }

  # Every account is seeded with an agent called Sofia the moment it is created,
  # so "the agents of this account" is never an empty list and these tests must
  # not pretend otherwise.
  def agent_names
    report[:agents].map { |row| row[:name] }
  end

  def log(agent = assistant, **attrs)
    create(:ai_invocation, { account: agent.account, ai_assistant: agent }.merge(attrs))
  end

  # A delivered reply is one message the customer received, whatever it cost in
  # calls to produce.
  def reply(agent = assistant, message_id:, **attrs)
    log(agent, message_id: message_id, conversation_id: attrs.delete(:conversation_id) || 1, **attrs)
  end

  def charge(invocation, cents)
    create(:ai_credit_ledger_entry, account: account, kind: 'consumption',
                                    amount_cents_brl: -cents, ai_invocation: invocation)
  end

  describe 'replies against calls' do
    # The distinction the whole panel rests on. A reply that used the scheduling
    # tools bills several calls, and counting calls as work makes a chatty agent
    # look productive precisely because it needed more attempts.
    it 'counts one reply for the several calls that produced it' do
      3.times { reply(message_id: 42) }

      expect(report[:totals][:replies]).to eq(1)
      expect(report[:totals][:calls]).to eq(3)
    end

    it 'counts the conversations a reply reached' do
      reply(message_id: 1, conversation_id: 10)
      reply(message_id: 2, conversation_id: 10)
      reply(message_id: 3, conversation_id: 11)

      expect(report[:totals][:conversations]).to eq(2)
    end

    it 'does not count a call that never produced a message' do
      log(phase: 'summary')

      expect(report[:totals][:replies]).to be_zero
      expect(report[:totals][:calls]).to eq(1)
    end
  end

  describe 'the playground' do
    # It costs real money, so hiding it would understate the bill. Nobody has to
    # review an answer given to a fake customer, so counting it as work or as
    # something to supervise would invent both.
    it 'is spend but never work' do
      log(sandbox: true, message_id: 7, conversation_id: 3, auto_flag: 'sem_fonte')

      expect(report[:totals][:calls]).to eq(1)
      expect(report[:totals][:replies]).to be_zero
      expect(report[:totals][:flagged]).to be_zero
    end
  end

  describe 'money' do
    # Not a conversion of the USD in the call log: that is what Anthropic
    # charged us, and this is what came off the customer's balance. Quoting the
    # first tells an operator a price nobody charged them.
    it 'reads spend from the ledger and not from the USD figure' do
      charge(log(cost_usd: 99.0), 250)

      expect(report[:totals][:cost_cents_brl]).to eq(250)
    end

    it 'divides the real spend by the conversations it served' do
      charge(reply(message_id: 1, conversation_id: 10), 300)
      charge(reply(message_id: 2, conversation_id: 11), 300)

      expect(report[:totals][:cost_per_conversation_brl]).to eq(3.0)
    end

    # Zero would read as "the agent works for free"; nothing reads as "nobody
    # asked it anything", which is what an empty month means.
    it 'leaves a unit cost empty rather than zero when nothing was served' do
      charge(log(phase: 'summary'), 500)

      expect(report[:totals][:cost_per_conversation_brl]).to be_nil
      expect(report[:totals][:cost_per_booking_brl]).to be_nil
    end

    it 'reports how much of the input never had to be paid at full price' do
      log(input_tokens: 250, cache_read_tokens: 750)

      expect(report[:totals][:cache_savings_ratio]).to eq(75.0)
    end
  end

  describe 'return on spend' do
    it 'divides attributed revenue by what was actually debited' do
      charge(log, 10_000)
      create(:ai_revenue_event, ai_assistant: assistant, amount_brl: 300.0)

      expect(report[:totals][:roi]).to eq(3.0)
    end

    # Revenue with no cost is not an infinite return, it is a month nobody has
    # been billed for yet.
    it 'stays empty while there is no spend to divide by' do
      create(:ai_revenue_event, ai_assistant: assistant, amount_brl: 300.0)

      expect(report[:totals][:roi]).to be_nil
    end
  end

  describe 'the agent by agent table' do
    let(:quiet) { create(:ai_assistant, account: account, name: 'Aurora') }

    before do
      reply(message_id: 1)
      reply(message_id: 2)
      reply(quiet, message_id: 3)
    end

    # The agent carrying the account is the first line, not an alphabetical
    # accident: 'Aurora' sorts before 'Marina' and answered a third as much, and
    # the seeded 'Sofia' answered nothing at all.
    it 'leads with the agent doing the work' do
      expect(agent_names).to eq(%w[Marina Aurora Sofia])
    end

    it 'gives every agent a row even when it did nothing' do
      idle = create(:ai_assistant, account: account, name: 'Parada')

      expect(report[:agents].map { |row| row[:id] }).to include(idle.id)
    end

    it 'attributes spend to the agent whose call caused it' do
      charge(reply(quiet, message_id: 9), 700)

      row = report[:agents].find { |agent| agent[:id] == quiet.id }
      expect(row[:cost_cents_brl]).to eq(700)
    end

    # So the screen can print an em dash instead of a zero for an agent whose
    # agenda we do not hold.
    it 'says which agenda each agent books on' do
      expect(report[:agents].first).to have_key(:agenda_provider)
    end
  end

  describe 'quality' do
    it 'separates the machine flagging itself from a human saying so' do
      log(message_id: 5, conversation_id: 1, auto_flag: 'preco_inventado')
      # A thumbs-down carries a reason or it is a shrug the model refuses.
      create(:ai_response_feedback, ai_assistant: assistant, rating: 'down', reason: 'info_incorreta')

      expect(report[:flags]['preco_inventado']).to eq(1)
      expect(report[:quality][:down]).to eq(1)
    end

    # A fresh account showing a perfect score is the panel inventing praise
    # nobody gave.
    it 'leaves approval empty until somebody reviews something' do
      log(message_id: 5, conversation_id: 1)

      expect(report[:quality][:approval_rate]).to be_nil
    end

    it 'counts a correction nobody applied, because it is work already done' do
      create(:ai_response_feedback, ai_assistant: assistant, rating: 'down',
                                    reason: 'info_incorreta', applied_at: nil)

      expect(report[:quality][:pending_application]).to eq(1)
    end
  end

  describe 'the series' do
    # GROUP BY only emits days that had traffic, so plotting it raw squeezes a
    # silent week into nothing and the chart shows a busy month that never was.
    it 'fills every day of the period, including the silent ones' do
      reply(message_id: 1)

      expect(report[:daily].length).to eq(30)
      expect(report[:daily].count { |row| row[:replies].positive? }).to eq(1)
    end

    it 'carries spend on the same day rows, in reais' do
      charge(reply(message_id: 1), 450)

      expect(report[:daily].sum { |row| row[:cost_cents_brl] }).to eq(450)
    end

    # A gap here is information: it is when the business is closed and the agent
    # is the only thing answering.
    it 'always reports all twenty four hours' do
      expect(report[:hourly].length).to eq(24)
      expect(report[:hourly].map { |row| row[:hour] }).to eq((0..23).to_a)
    end

    it 'names the clock the hours are read on' do
      expect(report[:timezone]).to be_present
    end
  end

  describe 'the boundary of the account' do
    # One global screen, many tenants. A number that crosses this line is the
    # worst bug this module could ship.
    it 'never counts another account' do
      other = create(:ai_assistant, name: 'Estranha')
      create(:ai_invocation, account: other.account, ai_assistant: other, message_id: 99, conversation_id: 99)
      create(:ai_revenue_event, ai_assistant: other, amount_brl: 5_000.0)

      expect(report[:totals][:replies]).to be_zero
      expect(report[:totals][:revenue_brl]).to eq(0.0)
      expect(agent_names).not_to include('Estranha')
    end
  end

  describe 'the period' do
    # Snapped rather than clamped, so one person cannot quote 43 days and
    # another 30 and both call it "the month".
    it 'snaps anything the screen does not offer back to the default' do
      expect(described_class.new(account: account, days: 43).perform[:period_days]).to eq(30)
      expect(described_class.new(account: account, days: 0).perform[:period_days]).to eq(30)
    end

    it 'accepts the periods the screen offers' do
      expect(described_class.new(account: account, days: 7).perform[:period_days]).to eq(7)
      expect(described_class.new(account: account, days: 90).perform[:period_days]).to eq(90)
    end

    it 'ignores what happened before the window' do
      travel_to(40.days.ago) { reply(message_id: 1) }

      expect(report[:totals][:replies]).to be_zero
    end
  end
end
