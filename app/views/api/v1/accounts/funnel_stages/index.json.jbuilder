json.array! @stages do |stage|
  json.partial! 'funnel_stage', stage: stage
end
