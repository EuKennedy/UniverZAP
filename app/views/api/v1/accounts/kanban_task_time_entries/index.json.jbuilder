json.array! @entries do |entry|
  json.merge! entry.push_event_data
end
