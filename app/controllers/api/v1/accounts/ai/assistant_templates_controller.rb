# Ready-made agents per vertical.
#
# Static content, so no account scoping is needed beyond being signed in: the
# templates are the same for everybody and contain nobody's data.
class Api::V1::Accounts::Ai::AssistantTemplatesController < Api::V1::Accounts::BaseController
  def index
    render json: { templates: Ai::AgentTemplates.summaries }
  end

  def show
    template = Ai::AgentTemplates.find(params[:id])
    return render json: { error: 'template not found' }, status: :not_found if template.blank?

    render json: template
  end
end
