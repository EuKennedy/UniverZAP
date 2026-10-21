json.payload @contact_lists do |contact_list|
  json.partial! 'contact_list', contact_list: contact_list, counts: @counts[contact_list.id]
end
