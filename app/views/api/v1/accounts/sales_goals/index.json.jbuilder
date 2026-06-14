json.array! @sales_goals do |sales_goal|
  json.partial! 'sales_goal', sales_goal: sales_goal
end
