json.array! @broadcasts do |broadcast|
  json.partial! 'broadcast', broadcast: broadcast
end
