json.payload do
  json.array! @agents do |agent|
    json.partial! 'api/v1/models/agent', formats: [:json], resource: agent
    json.assignment_capacity @capacities[agent.id]
  end
end
