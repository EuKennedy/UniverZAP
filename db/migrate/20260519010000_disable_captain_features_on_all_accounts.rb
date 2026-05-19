class DisableCaptainFeaturesOnAllAccounts < ActiveRecord::Migration[7.1]
  CAPTAIN_FEATURES = %i[captain_integration captain_integration_v2 captain_tasks captain_v1_action_classifier
                        captain_document_auto_sync custom_tools].freeze

  def up
    Account.find_each do |account|
      account.disable_features!(*CAPTAIN_FEATURES)
    rescue StandardError => e
      Rails.logger.warn("[CaptainHide] failed to disable features for account #{account.id}: #{e.message}")
    end
  end

  def down
    # no-op; re-enabling Captain is a manual super-admin action
  end
end
