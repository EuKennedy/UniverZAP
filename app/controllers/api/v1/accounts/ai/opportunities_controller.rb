# The commercial radar: conversations that ended without a sale, hottest first,
# and the actions an operator takes on them.
class Api::V1::Accounts::Ai::OpportunitiesController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_opportunity, only: %i[update]

  MAX_PAGE_SIZE = 50

  def index
    render json: {
      items: scope.hottest_first.limit(MAX_PAGE_SIZE).map(&:push_event_data),
      counts: counts,
      roi: Ai::RoiService.new(assistant: @assistant, days: params[:days] || 30).perform
    }
  end

  # Marking a lead won is the honest, immediate half of revenue attribution: the
  # person who closed the sale says so, and the ROI panel stops being a cost
  # report from that moment on.
  def update
    @opportunity.update!(permitted_params)
    record_revenue if @opportunity.status == 'won'
    render json: @opportunity.push_event_data
  end

  # Hands the selection to the broadcast dispatcher that already carries the
  # anti-ban throttle. Nothing is sent from here.
  def bulk_followup
    broadcast = Ai::FollowUpBroadcastService.new(
      assistant: @assistant, opportunity_ids: params[:opportunity_ids],
      message: params[:message], inbox: fetch_inbox
    ).perform
    render json: { broadcast_id: broadcast.id, recipients: broadcast.audience['contact_ids'].length }
  rescue Ai::FollowUpBroadcastService::NoRecipients => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    return nil if params[:inbox_id].blank?

    Current.account.inboxes.find_by(id: params[:inbox_id])
  end

  def scope
    base = @assistant.lead_opportunities
    base = base.where(status: params[:status]) if params[:status].present?
    base = base.public_send(params[:band]) if %w[hot warm cold].include?(params[:band].to_s)
    base
  end

  def counts
    {
      hot: @assistant.lead_opportunities.open_leads.hot.count,
      warm: @assistant.lead_opportunities.open_leads.warm.count,
      cold: @assistant.lead_opportunities.open_leads.cold.count
    }
  end

  # `find_or_create_by` on the opportunity: re-marking a lead won must not
  # credit the same sale twice.
  def record_revenue
    Ai::RevenueEvent.find_or_create_by!(ai_lead_opportunity_id: @opportunity.id) do |event|
      event.assign_attributes(
        ai_assistant: @assistant, account: Current.account,
        conversation_id: @opportunity.conversation_id, contact_id: @opportunity.contact_id,
        source: 'recuperado', amount_brl: @opportunity.won_brl || @opportunity.potential_brl,
        occurred_at: Time.current, recorded_by: 'operator'
      )
    end
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def fetch_opportunity
    @opportunity = @assistant.lead_opportunities.find(params[:id])
  end

  def permitted_params
    params.require(:opportunity).permit(:status, :won_brl, :suggested_action)
  end
end
