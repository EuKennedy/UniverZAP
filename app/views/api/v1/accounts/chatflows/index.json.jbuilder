json.array! @chatflows do |chatflow|
  json.partial! 'chatflow', chatflow: chatflow
  json.stats @stats.fetch(chatflow.id, { 'started' => 0, 'completed' => 0, 'live' => 0 })
end
