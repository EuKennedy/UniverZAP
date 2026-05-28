# Move the task to a different funnel + stage on the SAME account.
# Use when a card graduates from "Sales" to "Onboarding" pipeline.
#
# Params:
#   funnel_id (Integer, required)
#   stage_id  (Integer, required) — must belong to the target funnel
#
# Critical: cross-funnel moves with bad ids leave the task in a
# half-migrated state otherwise.
class Kanban::Automations::Actions::MoveToFunnel < Kanban::Automations::Actions::Base
  def critical?
    true
  end

  private

  def perform!
    target_funnel = account.funnels.find_by(id: required_param!(:funnel_id).to_i)
    raise ExecutionError, "funnel_id=#{params[:funnel_id]} not on account" if target_funnel.nil?

    target_stage = target_funnel.funnel_stages.find_by(id: required_param!(:stage_id).to_i)
    raise ExecutionError, "stage_id=#{params[:stage_id]} not in funnel=#{target_funnel.id}" if target_stage.nil?

    return if task.funnel_id == target_funnel.id && task.funnel_stage_id == target_stage.id

    position = (target_stage.kanban_tasks.maximum(:position) || 0) + 1
    task.update!(funnel: target_funnel, funnel_stage: target_stage, position: position)
  end
end
