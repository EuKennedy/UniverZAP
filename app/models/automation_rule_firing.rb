# == Schema Information
#
# Table name: automation_rule_firings
#
#  id                 :bigint           not null, primary key
#  dedupe_key         :string           not null
#  created_at         :datetime         not null
#  automation_rule_id :bigint           not null
#  conversation_id    :bigint           not null
#
# Indexes
#
#  index_automation_rule_firings_on_automation_rule_id  (automation_rule_id)
#  index_automation_rule_firings_on_conversation_id     (conversation_id)
#  index_automation_rule_firings_unique                 (automation_rule_id,conversation_id,dedupe_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (automation_rule_id => automation_rules.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#
# One row per time a scanned (time-based) rule fired on a conversation. The
# dedupe_key names the period that fired it (the waiting_since timestamp), so
# a rule runs once per wait and again when the customer waits anew.
class AutomationRuleFiring < ApplicationRecord
  belongs_to :automation_rule
  belongs_to :conversation

  validates :dedupe_key, presence: true, uniqueness: { scope: [:automation_rule_id, :conversation_id] }
end
