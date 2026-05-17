json.payload do
  json.array! @trainings do |training|
    json.merge! training.push_event_data
  end
end
