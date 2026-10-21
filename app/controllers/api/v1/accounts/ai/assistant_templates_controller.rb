# Ready-made agents per vertical.
#
# Static content that contains nobody's data; the account only decides which
# of them fit its vertical.
class Api::V1::Accounts::Ai::AssistantTemplatesController < Api::V1::Accounts::BaseController
  # The account's vertical picks the templates that fit it (an e-commerce
  # account does not get the salon receptionist); a vertical without a
  # preference sees all of them.
  def index
    keys = VerticalProfile.for(Current.account).agent_templates
    templates = Ai::AgentTemplates.summaries
    templates = templates.select { |template| keys.include?(template[:key]) } if keys.any?
    render json: { templates: templates }
  end

  def show
    template = Ai::AgentTemplates.find(params[:id])
    return render json: { error: 'template not found' }, status: :not_found if template.blank?

    render json: template
  end
end
