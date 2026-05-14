json.array! @tasks do |task|
  json.partial! 'kanban_task', task: task
end
