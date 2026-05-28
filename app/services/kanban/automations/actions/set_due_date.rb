# Set or clear the task's due_date.
# Mutually exclusive params (one required):
#   in_hours  (Numeric)  — relative offset from now (e.g. 24, 72)
#   in_days   (Numeric)  — relative offset from now (e.g. 3, 7)
#   at        (String)   — absolute ISO8601 timestamp ("2026-05-30T18:00:00Z")
#   clear     (Boolean)  — true to wipe the due_date
class Kanban::Automations::Actions::SetDueDate < Kanban::Automations::Actions::Base
  private

  def perform!
    if ActiveModel::Type::Boolean.new.cast(params[:clear])
      task.update!(due_date: nil)
      return
    end

    target = resolve_target
    raise ExecutionError, 'one of in_hours/in_days/at/clear is required' if target.nil?

    task.update!(due_date: target)
  end

  def resolve_target
    return Time.current + params[:in_hours].to_f.hours if params[:in_hours].present?
    return Time.current + params[:in_days].to_f.days if params[:in_days].present?
    return Time.zone.parse(params[:at].to_s) if params[:at].present?

    nil
  end
end
