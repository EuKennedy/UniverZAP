# Decides whether a `conversation_label_added` rule applies to the labels that
# were JUST added to a conversation. A plain `conversation_updated` rule with
# `labels equal_to X` fires on every later update while X is present; this one
# fires once, at the moment X arrives — which is what "status changed TO X"
# means for the vertical statuses.
#
# Label conditions are checked against the added labels; every other condition
# goes through the regular ConditionsFilterService on the conversation.
class AutomationRules::LabelAddedMatcher
  def initialize(rule, conversation, added_labels)
    @rule = rule
    @conversation = conversation
    @added = Array(added_labels).map(&:to_s)
  end

  def match?
    label_conditions, other_conditions = @rule.conditions.partition { |c| c['attribute_key'] == 'labels' }
    return false unless label_conditions.all? { |condition| label_condition_met?(condition) }
    return true if other_conditions.empty?

    AutomationRules::ConditionsFilterService.new(rule_without_labels(other_conditions), @conversation, {}).perform
  end

  private

  def label_condition_met?(condition)
    value = Array(condition['values']).first.to_s
    case condition['filter_operator']
    when 'equal_to' then @added.include?(value)
    when 'not_equal_to' then @added.exclude?(value)
    else true
    end
  end

  # The remaining conditions still chain with their own AND/OR; the last one
  # just must not dangle an operator.
  def rule_without_labels(conditions)
    rest = conditions.map(&:dup)
    rest.last['query_operator'] = nil
    @rule.dup.tap { |copy| copy.conditions = rest }
  end
end
