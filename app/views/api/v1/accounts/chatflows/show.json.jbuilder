json.partial! 'chatflow', chatflow: @chatflow

json.nodes @nodes do |node|
  json.partial! 'node', node: node
end

json.edges @edges do |edge|
  json.partial! 'edge', edge: edge
end
