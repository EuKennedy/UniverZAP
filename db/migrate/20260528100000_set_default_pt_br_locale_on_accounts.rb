class SetDefaultPtBrLocaleOnAccounts < ActiveRecord::Migration[7.1]
  # Originally flipped the schema-level default to 16 (pt_BR). Reverted
  # because upstream Chatwoot specs assert English literal copy
  # everywhere a conversation activity message is generated, and the
  # cascade of "Assigned to X by Y" → "Atribuído a X por Y" failures
  # in CI showed the schema default was the wrong layer to enforce
  # locale. The UniverZAP-only default still happens at the
  # application layer via `Connect::SetupController.ensure_user_has_account`
  # so every Univercart-provisioned account is created with
  # `locale: 'pt_BR'` explicitly — without forcing the same on every
  # account factory in the test suite.
  def up
    # no-op
  end

  def down
    # no-op
  end
end
