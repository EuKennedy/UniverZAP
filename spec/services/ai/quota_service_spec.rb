# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::QuotaService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  describe '#check!' do
    context 'when the account has a healthy balance and no daily spend' do
      it 'returns nil and never raises' do
        # Default starter grant covers a normal Sonnet call.
        expect do
          described_class.check!(account: account, model: 'claude-sonnet-4-5', max_output_tokens: 256)
        end.not_to raise_error
      end
    end

    context 'when the daily USD cap has already been spent' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('ATHENAS_DAILY_USD_CAP', anything).and_return('1.0')

        create(
          :ai_invocation,
          account: account,
          ai_assistant: assistant,
          cost_usd: 1.5,
          phase: 'main',
          status: 'success',
          model: 'claude-sonnet-4-5'
        )
      end

      it 'raises QuotaExhaustedError with reason daily_cap' do
        expect do
          described_class.check!(account: account, model: 'claude-sonnet-4-5', max_output_tokens: 256)
        end.to raise_error(Ai::CreditLedger::QuotaExhaustedError) { |error|
          expect(error.reason).to eq('daily_cap')
        }
      end
    end

    context 'when the account custom_attributes override sets a higher daily cap' do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('ATHENAS_DAILY_USD_CAP', anything).and_return('1.0')
        account.update!(custom_attributes: { 'athenas_daily_usd_cap' => '10.0' })

        create(
          :ai_invocation,
          account: account,
          ai_assistant: assistant,
          cost_usd: 1.5,
          phase: 'main',
          status: 'success',
          model: 'claude-sonnet-4-5'
        )
      end

      it 'allows the call because per-account override beats env default' do
        expect do
          described_class.check!(account: account, model: 'claude-sonnet-4-5', max_output_tokens: 256)
        end.not_to raise_error
      end
    end

    context 'when the BRL credit ledger is exhausted (no grace remaining)' do
      before do
        account.update!(
          token_credit_balance_cents_brl: 0,
          token_credit_grace_used: true
        )
      end

      it 'raises QuotaExhaustedError with reason balance' do
        expect do
          described_class.check!(account: account, model: 'claude-sonnet-4-5', max_output_tokens: 256)
        end.to raise_error(Ai::CreditLedger::QuotaExhaustedError) { |error|
          expect(error.reason).to eq('balance')
        }
      end
    end

    context 'when the BRL ledger is empty but grace has not been used yet' do
      before do
        account.update!(token_credit_balance_cents_brl: 0, token_credit_grace_used: false)
        create(:ai_credit_ledger_entry, account: account, kind: 'grant', amount_cents_brl: 10_000)
      end

      it 'grants the one-shot grace top-up and lets the call through' do
        expect do
          described_class.check!(account: account, model: 'claude-haiku-4-5', max_output_tokens: 128)
        end.not_to raise_error
        expect(account.reload.token_credit_grace_used).to be true
      end
    end
  end

  describe '.usage_summary' do
    it 'exposes daily USD cap and current daily spend alongside ledger summary' do
      summary = described_class.usage_summary(account: account)
      expect(summary).to include(:balance_cents_brl, :daily_usd_cap, :daily_usd_spent)
      expect(summary[:daily_usd_cap]).to be_a(Numeric)
      expect(summary[:daily_usd_spent]).to be_a(Numeric)
    end
  end
end
