json.payload do
  json.array! @inbox_groups, partial: 'api/v1/accounts/inbox_groups/inbox_group', as: :inbox_group
end
