json.array! @sale_records do |sale_record|
  json.partial! 'sale_record', sale_record: sale_record
end
