# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CreditLedger do
  let(:account) { create(:account) }
  let(:ledger)  { described_class.new(account) }

  describe '#balance_cents' do
    it 'mirrors the denormalized cache column on Account' do
      account.update_columns(token_credit_balance_cents_brl: 1_234)
      expect(ledger.balance_cents).to eq(1_234)
    end
  end

  describe '#enough?' do
    it 'returns true when the balance covers the attempted cost' do
      account.update_columns(token_credit_balance_cents_brl: 1_000)
      expect(ledger.enough?(500)).to be true
    end

    it 'returns false when the attempted cost exceeds the balance' do
      account.update_columns(token_credit_balance_cents_brl: 100)
      expect(ledger.enough?(500)).to be false
    end
  end

  describe '#debit!' do
    it 'creates a negative consumption entry and decrements the cache' do
      account.update_columns(token_credit_balance_cents_brl: 2_500)

      expect {
        ledger.debit!(invocation: nil, cents_brl: 400, description: 'test')
      }.to change(Ai::CreditLedgerEntry, :count).by(1)

      expect(account.reload.token_credit_balance_cents_brl).to eq(2_100)
      latest = account.ai_credit_ledger_entries.recent.first
      expect(latest.kind).to eq('consumption')
      expect(latest.amount_cents_brl).to eq(-400)
    end
  end

  describe '#credit_purchase!' do
    it 'increments balance + lifetime purchased and is idempotent per external_payment_id' do
      ledger.credit_purchase!(cents_brl: 5_000, external_payment_id: 'pay_abc')
      ledger.credit_purchase!(cents_brl: 5_000, external_payment_id: 'pay_abc') # duplicate webhook

      account.reload
      expect(account.token_credit_balance_cents_brl).to eq(2_500 + 5_000)
      expect(account.token_credit_lifetime_purchased_cents_brl).to eq(5_000)
      expect(account.ai_credit_ledger_entries.purchases.count).to eq(1)
    end
  end

  describe '#grant_grace!' do
    it 'is single-shot and bumps balance by at least 250 cents' do
      account.update_columns(token_credit_balance_cents_brl: 0)
      expect(ledger.grant_grace!).to be true
      expect(account.reload.token_credit_balance_cents_brl).to be >= 250
      expect(account.token_credit_grace_used).to be true

      # Second call is a no-op
      expect(ledger.grant_grace!).to be false
    end
  end

  describe '#threshold_status' do
    before { account.ai_credit_ledger_entries.delete_all }

    it 'returns :ok when no credits have ever been granted' do
      expect(ledger.threshold_status).to eq(:ok)
    end

    it 'returns :exhausted when balance hits zero' do
      create(:ai_credit_ledger_entry, account: account, kind: 'grant', amount_cents_brl: 10_000)
      account.update_columns(token_credit_balance_cents_brl: 0)
      expect(ledger.threshold_status).to eq(:exhausted)
    end

    it 'returns :warn_95 when balance is at or below 5% of granted' do
      create(:ai_credit_ledger_entry, account: account, kind: 'grant', amount_cents_brl: 10_000)
      account.update_columns(token_credit_balance_cents_brl: 400)
      expect(ledger.threshold_status).to eq(:warn_95)
    end

    it 'returns :warn_80 when balance is at or below 20% of granted' do
      create(:ai_credit_ledger_entry, account: account, kind: 'grant', amount_cents_brl: 10_000)
      account.update_columns(token_credit_balance_cents_brl: 1_500)
      expect(ledger.threshold_status).to eq(:warn_80)
    end
  end
end
