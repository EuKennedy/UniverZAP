json.payload do
  json.array! @scheduled_messages do |scheduled_message|
    json.partial! 'scheduled_message', scheduled_message: scheduled_message
  end
end
