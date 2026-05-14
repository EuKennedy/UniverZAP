json.array! @funnels do |funnel|
  json.partial! 'funnel', funnel: funnel
end
