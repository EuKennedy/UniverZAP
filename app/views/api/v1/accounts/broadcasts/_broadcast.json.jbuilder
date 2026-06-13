json.id broadcast.id
json.account_id broadcast.account_id
json.inbox_id broadcast.inbox_id
json.name broadcast.name
json.mode broadcast.mode
json.status broadcast.status
json.message broadcast.message
json.audience broadcast.audience
json.throttle broadcast.throttle
json.scheduled_at broadcast.scheduled_at
json.recipients_count broadcast.broadcast_recipients.count
json.sent_count broadcast.broadcast_recipients.where(status: [:sent, :delivered, :read]).count
json.failed_count broadcast.broadcast_recipients.status_failed.count
json.created_at broadcast.created_at.to_i
json.updated_at broadcast.updated_at.to_i
