class DefaultAccountsLocaleToPtBr < ActiveRecord::Migration[7.1]
  # UniverZAP is a Brazilian product: the dashboard must default to pt-BR.
  # New accounts default to pt_BR and any account still on the upstream
  # default ("en") is migrated over.
  def up
    change_column_default :accounts, :locale, from: 'en', to: 'pt_BR'
    # rubocop:disable Rails/SkipsModelValidations
    Account.where(locale: 'en').update_all(locale: 'pt_BR')
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
    change_column_default :accounts, :locale, from: 'pt_BR', to: 'en'
  end
end
