json.array! @chatflows do |chatflow|
  json.partial! 'chatflow', chatflow: chatflow
end
