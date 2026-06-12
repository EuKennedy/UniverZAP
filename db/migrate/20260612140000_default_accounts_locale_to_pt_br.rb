class DefaultAccountsLocaleToPtBr < ActiveRecord::Migration[7.1]
  # UniverZAP is a pt-BR product. New accounts already get locale 'pt_BR'
  # at the application layer (Connect::SetupController / BridgeController).
  #
  # We intentionally DO NOT change the schema-level default: migration
  # 20260528100000 documents that forcing it there cascades upstream
  # Chatwoot spec failures (English activity-message assertions). This is a
  # data-only backfill so existing accounts still on the upstream "en"
  # default render the dashboard in Portuguese.
  def up
    # rubocop:disable Rails/SkipsModelValidations
    Account.where(locale: 'en').update_all(locale: 'pt_BR')
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
    # no-op — locale backfill is not reversible.
  end
end
