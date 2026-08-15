# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Reports::AccountClock do
  let(:account) { create(:account) }
  let(:clock) { described_class.new(account) }

  # Nothing sets config.time_zone on this installation, so the fallback is UTC
  # and every hour in the panel would be three off for a Brazilian operator.
  # That is exactly the failure this class exists to prevent, so it is worth
  # pinning: the default is the last resort and not the answer.
  it 'falls back to the installation clock when nobody has said anything' do
    expect(clock.tz_name).to eq(Time.zone.tzinfo.name)
  end

  context 'when an inbox carries a timezone somebody chose' do
    it 'reads the account clock from it' do
      create(:inbox, account: account, timezone: 'America/Sao_Paulo')

      expect(clock.tz_name).to eq('America/Sao_Paulo')
    end

    # Chatwoot ships 'UTC' on every inbox, so the default is not a statement
    # about where the business is and must not be read as one.
    it 'ignores the default nobody chose' do
      create(:inbox, account: account, timezone: 'UTC')

      expect(clock.tz_name).to eq(Time.zone.tzinfo.name)
    end
  end

  context 'when the agenda has a timezone' do
    let(:assistant) { create(:ai_assistant, account: account) }

    before do
      connection = Ai::Calendar::Connection.create!(
        ai_assistant: assistant, account: account, google_email: 'salao@example.com',
        encrypted_refresh_token: 'token', status: 'active'
      )
      connection.professionals.create!(
        ai_assistant_id: assistant.id, account_id: account.id,
        name: 'Marcela', calendar_id: 'primary', timezone: 'America/Recife'
      )
    end

    # The operator typed this one by hand and the agent books real appointments
    # against it, so a wrong value there would already be visible to them.
    it 'trusts it over an inbox' do
      create(:inbox, account: account, timezone: 'America/Sao_Paulo')

      expect(clock.tz_name).to eq('America/Recife')
    end
  end

  # A name TZInfo refuses must not take the whole report down over a chart axis.
  # Written past the model's own validation on purpose: the row can only get
  # into that state from outside Rails, which is exactly the case worth covering.
  it 'falls through a timezone it cannot resolve' do
    inbox = create(:inbox, account: account, timezone: 'America/Sao_Paulo')
    # Skipping the validation IS the test: the model rejects this value, so the
    # only way the column ever holds it is a write from outside Rails, and that
    # is the case the fallback exists for.
    inbox.update_column(:timezone, 'Mars/Olympus_Mons') # rubocop:disable Rails/SkipsModelValidations

    expect(clock.tz_name).to eq(Time.zone.tzinfo.name)
  end
end
