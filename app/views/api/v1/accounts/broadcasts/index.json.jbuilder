json.array! @broadcasts do |broadcast|
  json.partial! 'broadcast', broadcast: broadcast, counts: @counts[broadcast.id]
end
