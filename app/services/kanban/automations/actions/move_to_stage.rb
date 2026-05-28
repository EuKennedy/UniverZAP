# Move the task to a different stage in the SAME funnel.
# Params:
#   stage_id (Integer, required) — target FunnelStage id, must belong to
#     `task.funnel`. Cross-funnel moves use `move_to_funnel` instead.
#   position (Integer, optional) — target position within the new stage;
#     defaults to last position.
#
# Critical: a mistyped stage_id is a config bug, not a transient issue.
class Kanban::Automations::Actions::MoveToStage < Kanban::Automations::Actions::Base
  def critical?
    true
  end

  private

  def perform!
    stage_id = required_param!(:stage_id).to_i
    stage = funnel.funnel_stages.find_by(id: stage_id)
    raise ExecutionError, "stage_id=#{stage_id} not in funnel=#{funnel.id}" if stage.nil?

    # Same stage = no-op (don't fire stage_changed again).
    return if task.funnel_stage_id == stage.id

    target_position = params[:position].presence&.to_i ||
                      (stage.kanban_tasks.maximum(:position) || 0) + 1
    task.update!(funnel_stage: stage, position: target_position)
  end
end
