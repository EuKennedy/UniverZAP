# Assign one or more atendentes to the task. Replaces the existing
# assignees by default; pass `mode: 'append'` to add without removing.
#
# Params:
#   user_ids (Array<Integer>, required) — must be account_users of the
#     account; cross-tenant ids are silently filtered out.
#   mode (String, default 'replace') — 'replace' | 'append'
class Kanban::Automations::Actions::AssignUser < Kanban::Automations::Actions::Base
  private

  def perform!
    ids = Array(params[:user_ids]).map(&:to_i).reject(&:zero?)
    raise ExecutionError, 'user_ids required' if ids.empty?

    valid_ids = account.users.where(id: ids).pluck(:id)
    raise ExecutionError, "no valid user_ids in #{ids.inspect}" if valid_ids.empty?

    mode = params[:mode].to_s.presence || 'replace'
    final_ids = mode == 'append' ? (task.assignee_ids + valid_ids).uniq : valid_ids
    task.assignee_ids = final_ids
  end
end
