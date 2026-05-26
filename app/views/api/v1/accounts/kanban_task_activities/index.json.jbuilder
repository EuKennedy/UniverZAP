json.array! @activities do |activity|
  json.merge! activity.push_event_data
end
