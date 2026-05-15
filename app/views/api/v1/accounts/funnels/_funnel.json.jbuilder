json.id funnel.id
json.account_id funnel.account_id
json.name funnel.name
json.description funnel.description
json.position funnel.position
json.automation_settings funnel.automation_settings
json.inbox_ids funnel.inbox_ids
json.agent_ids funnel.agent_ids
json.tasks_count funnel.kanban_tasks.count
json.stages(funnel.funnel_stages.ordered.map { |stage| render('api/v1/accounts/funnel_stages/funnel_stage', stage: stage) })
json.created_at funnel.created_at.to_i
json.updated_at funnel.updated_at.to_i
