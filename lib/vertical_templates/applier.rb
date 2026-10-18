## Applies a vertical's flow template (statuses, custom attributes, automation rules)
## to an account. Safe to run on any account, new or existing: it only creates
## what's missing and never touches or deletes existing data.
##
## Statuses (labels) live in the Vertical/VerticalStatus tables, editable from
## Super Admin. Custom attributes and automation rules still come from the YAML
## files in templates/, when one exists for the vertical's key — a brand new
## vertical created purely through the UI simply won't have any.
############################################################
### Usage #####
#
#   VerticalTemplates::Applier.available_verticals
#   # => ["beauty_salon", "ecommerce"]
#
#   VerticalTemplates::Applier.new(account: Account.find(1), vertical: 'beauty_salon').perform!
#
############################################################

class VerticalTemplates::Applier
  TEMPLATES_DIR = Rails.root.join('lib/vertical_templates/templates')

  def self.available_verticals
    Vertical.order(:name).pluck(:key)
  end

  def initialize(account:, vertical:)
    @account = account
    @vertical = Vertical.find_by!(key: vertical.to_s)
    @template = load_template
  end

  def perform!
    apply_labels
    apply_custom_attribute_definitions
    apply_automation_rules
    @account.custom_attributes['vertical_template'] = @vertical.key
    @account.save!
  end

  private

  def load_template
    path = TEMPLATES_DIR.join("#{@vertical.key}.yml")
    File.exist?(path) ? YAML.safe_load(path.read) : {}
  end

  def apply_labels
    @vertical.vertical_statuses.each do |status|
      @account.labels.find_or_create_by!(title: status.title) do |record|
        record.color = status.color
        record.description = status.description
        record.closes_conversation = status.closes_conversation
      end
    end
  end

  def apply_custom_attribute_definitions
    (@template['custom_attribute_definitions'] || []).each do |attribute|
      @account.custom_attribute_definitions.find_or_create_by!(
        attribute_key: attribute['attribute_key'],
        attribute_model: attribute['attribute_model']
      ) do |record|
        record.attribute_display_name = attribute['attribute_display_name']
        record.attribute_display_type = attribute['attribute_display_type']
        record.attribute_description = attribute['attribute_description']
        record.attribute_values = attribute['attribute_values'] || []
      end
    end
  end

  def apply_automation_rules
    (@template['automation_rules'] || []).each do |rule|
      @account.automation_rules.find_or_create_by!(name: rule['name']) do |record|
        record.description = rule['description']
        record.event_name = rule['event_name']
        record.conditions = rule['conditions'] || []
        record.actions = rule['actions']
      end
    end
  end
end
