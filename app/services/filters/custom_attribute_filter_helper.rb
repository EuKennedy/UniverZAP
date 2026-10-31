module Filters::CustomAttributeFilterHelper
  def custom_attribute_query(query_hash, custom_attribute_type, current_index)
    @attribute_key = query_hash[:attribute_key]
    @custom_attribute_type = custom_attribute_type
    attribute_data_type
    return '' if @custom_attribute.blank?

    build_custom_attr_query(query_hash, current_index)
  end

  private

  def attribute_model
    @attribute_model = @custom_attribute_type.presence || self.class::ATTRIBUTE_MODEL
  end

  def attribute_data_type
    attribute_type = custom_attribute(@attribute_key, @account, attribute_model).try(:attribute_display_type)
    @attribute_data_type = self.class::ATTRIBUTE_TYPES[attribute_type]
  end

  def build_custom_attr_query(query_hash, current_index)
    filter_operator_value = filter_operation(query_hash, current_index)
    query_operator = query_hash[:query_operator]
    table_name = attribute_model == 'conversation_attribute' ? 'conversations' : 'contacts'

    value = custom_attr_value_sql(table_name)
    condition = "#{value} #{filter_operator_value}"
    # "Is not X" also matches contacts that never had the attribute. Grouped so
    # the OR cannot swallow the conditions around it.
    condition = "(#{condition} OR #{value} IS NULL)" if query_hash[:filter_operator] == 'not_equal_to'

    "#{condition} #{query_operator} "
  end

  def custom_attr_value_sql(table_name)
    template = attribute_data_type == 'text' ? 'LOWER(%s.custom_attributes ->> ?)::%s' : '(%s.custom_attributes ->> ?)::%s'
    ActiveRecord::Base.sanitize_sql_array([format(template, table_name, attribute_data_type), @attribute_key])
  end

  def custom_attribute(attribute_key, account, custom_attribute_type)
    current_account = account || Current.account
    attribute_model = custom_attribute_type.presence || self.class::ATTRIBUTE_MODEL
    @custom_attribute = current_account.custom_attribute_definitions.where(
      attribute_model: attribute_model
    ).find_by(attribute_key: attribute_key)
  end
end
