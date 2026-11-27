# Conta nova não ganha mais crédito de IA: o saldo começa em zero e o crédito
# vem só de compra. As contas que já existem ficam com o saldo que têm.
class RemoveFreeAiCreditFromNewAccounts < ActiveRecord::Migration[7.1]
  def change
    change_column_default :accounts, :token_credit_balance_cents_brl, from: 2_500, to: 0
  end
end
