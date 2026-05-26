json.array! @fields do |field|
  json.partial! 'funnel_custom_field', field: field
end
