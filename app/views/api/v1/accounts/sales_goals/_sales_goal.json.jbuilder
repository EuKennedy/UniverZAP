json.id sales_goal.id
json.user_id sales_goal.user_id
json.user do
  json.id sales_goal.user.id
  json.name sales_goal.user.name
  json.thumbnail sales_goal.user.avatar_url
end
json.name sales_goal.name
json.unit sales_goal.unit
json.category sales_goal.category
json.period sales_goal.period
json.target_amount sales_goal.target_amount
json.active sales_goal.active
json.progress do
  progress = sales_goal.progress
  json.target progress[:target]
  json.current progress[:current]
  json.remaining progress[:remaining]
  json.percent progress[:percent]
end
json.created_at sales_goal.created_at.to_i
