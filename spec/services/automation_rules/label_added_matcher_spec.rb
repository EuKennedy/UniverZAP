require 'rails_helper'

RSpec.describe AutomationRules::LabelAddedMatcher do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, status: :open) }

  def rule_with(conditions)
    create(:automation_rule, account: account, event_name: 'conversation_label_added', conditions: conditions)
  end

  it 'matches when the label that was just added is the one the rule names' do
    rule = rule_with([{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['agendado'], 'query_operator' => nil }])

    expect(described_class.new(rule, conversation, %w[agendado]).match?).to be true
    expect(described_class.new(rule, conversation, %w[cancelado]).match?).to be false
  end

  it 'ignores labels the conversation already had' do
    rule = rule_with([{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['agendado'], 'query_operator' => nil }])
    conversation.add_labels(%w[agendado])

    expect(described_class.new(rule, conversation, %w[confirmado]).match?).to be false
  end

  it 'supports not_equal_to on the added label' do
    rule = rule_with([{ 'attribute_key' => 'labels', 'filter_operator' => 'not_equal_to', 'values' => ['cancelado'], 'query_operator' => nil }])

    expect(described_class.new(rule, conversation, %w[agendado]).match?).to be true
    expect(described_class.new(rule, conversation, %w[cancelado]).match?).to be false
  end

  it 'still checks the other conditions against the conversation' do
    rule = rule_with([
                       { 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['agendado'], 'query_operator' => 'AND' },
                       { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }
                     ])

    expect(described_class.new(rule, conversation, %w[agendado]).match?).to be true
    conversation.update!(status: :pending)
    expect(described_class.new(rule, conversation, %w[agendado]).match?).to be false
  end

  it 'matches any added label when the rule has no label condition' do
    rule = rule_with([])

    expect(described_class.new(rule, conversation, %w[qualquer]).match?).to be true
  end
end
