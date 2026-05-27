FactoryBot.define do
  factory :ai_credit_ledger_entry, class: 'Ai::CreditLedgerEntry' do
    account
    kind { 'grant' }
    amount_cents_brl { 2_500 }
    description { 'Initial starter grant' }
  end
end
