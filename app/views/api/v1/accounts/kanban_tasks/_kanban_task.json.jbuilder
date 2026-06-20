json.id task.id
json.display_id task.display_id
json.account_id task.account_id
json.funnel_id task.funnel_id
json.funnel_stage_id task.funnel_stage_id
json.title task.title
json.description task.description
json.priority task.priority
json.position task.position
json.start_date task.start_date&.to_i
json.due_date task.due_date&.to_i
json.assignees(task.assignees.map { |u| { id: u.id, name: u.name, avatar_url: u.avatar_url } })
json.labels(task.task_labels.map { |l| { id: l.id, title: l.title, color: l.color } })
json.conversations(task.conversations.map { |c| { id: c.id, display_id: c.display_id, status: c.status, inbox_id: c.inbox_id } })
json.contacts(task.contacts.map { |c| { id: c.id, name: c.name, email: c.email, phone_number: c.phone_number, thumbnail: c.avatar_url } })
json.files(task.files.map do |file|
  {
    id: file.id,
    signed_id: file.blob.signed_id,
    name: file.blob.filename.to_s,
    byte_size: file.blob.byte_size,
    url: Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)
  }
end)
json.created_at task.created_at.to_i
json.updated_at task.updated_at.to_i
