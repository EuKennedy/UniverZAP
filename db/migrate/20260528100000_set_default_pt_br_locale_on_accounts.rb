class SetDefaultPtBrLocaleOnAccounts < ActiveRecord::Migration[7.1]
  # Account#locale is an integer enum (LANGUAGES_CONFIG). 16 = pt_BR,
  # 0 = en. UniverZAP ships exclusively to Brazilian operators, so the
  # column default flips to pt_BR going forward — every new account is
  # created with locale=16 unless the caller passes something else
  # explicitly. Existing rows stay on whatever they had to avoid
  # surprising tenants who picked a different language manually.
  def up
    change_column_default :accounts, :locale, from: 0, to: 16
  end

  def down
    change_column_default :accounts, :locale, from: 16, to: 0
  end
end
