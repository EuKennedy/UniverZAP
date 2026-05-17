json.payload do
  json.array! @assistants do |assistant|
    json.merge! assistant.push_event_data
  end
end
