json.array! @flows do |flow|
  json.partial! 'whatsapp_flow', flow: flow
end
