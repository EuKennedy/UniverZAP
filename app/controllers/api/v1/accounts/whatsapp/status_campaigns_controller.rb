# Campanhas de status: o fluxo de passos, as conexões, a data de início, o
# ciclo e a repostagem. Ativar entrega a campanha ao Planner, que agenda os
# próximos posts; pausar tira do calendário o que ainda não saiu.
class Api::V1::Accounts::Whatsapp::StatusCampaignsController < Api::V1::Accounts::BaseController
  STEP_ATTRIBUTES = %i[id kind body background_color font day_offset time_of_day repost_count repost_interval_hours blob_id].freeze
  PREVIEW_LIMIT = 8

  before_action :ensure_administrator
  before_action :fetch_campaign, only: [:show, :update, :destroy, :activate, :pause, :preview]

  def index
    campaigns = filtered.includes(:folder, steps: { media_attachment: :blob }).order(updated_at: :desc)
    next_at = Current.account.whatsapp_status_posts.status_scheduled.where(campaign_id: campaigns.map(&:id))
                     .group(:campaign_id).minimum(:scheduled_at)
    render json: { payload: campaigns.map { |campaign| summary(campaign, next_at[campaign.id]) } }
  end

  def show
    render json: detail(@campaign)
  end

  def create
    campaign = Current.account.whatsapp_status_campaigns.new(user: current_user)
    save(campaign)
  end

  def update
    save(@campaign)
  end

  def destroy
    @campaign.unschedule_future!
    @campaign.destroy!
    head :ok
  end

  def activate
    @campaign.update!(status: :active)
    replan(@campaign)
    render json: detail(@campaign.reload)
  end

  def pause
    @campaign.update!(status: :paused)
    @campaign.unschedule_future!
    render json: detail(@campaign.reload)
  end

  # As próximas saídas como ficariam, sem agendar nada: o editor mostra antes
  # de o operador ativar.
  def preview
    occurrences = Whatsapp::StatusCampaigns::Planner.new(@campaign).occurrences(until_at: 60.days.from_now).first(PREVIEW_LIMIT)
    render json: { payload: occurrences.map { |occurrence| occurrence_payload(occurrence) } }
  end

  private

  def ensure_administrator
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_campaign
    @campaign = Current.account.whatsapp_status_campaigns.find(params[:id])
  end

  def filtered
    scope = Current.account.whatsapp_status_campaigns
    scope = scope.where(folder_id: params[:folder_id] == 'none' ? nil : params[:folder_id]) if params[:folder_id].present?
    scope = scope.where(status: params[:status]) if WhatsappStatusCampaign.statuses.key?(params[:status])
    term = params[:q].to_s.strip
    term.present? ? scope.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%") : scope
  end

  # Campanha e passos numa transação só: um passo inválido não deixa a
  # campanha meio salva. Se ela está ativa, o que estava agendado para o
  # futuro sai e é refeito com o fluxo novo.
  def save(campaign)
    ActiveRecord::Base.transaction do
      campaign.assign_attributes(campaign_params)
      campaign.save!
      sync_steps(campaign) if params.key?(:steps)
      campaign.reload.validate! if campaign.status_active?
    end
    replan(campaign) if campaign.status_active?
    render json: detail(campaign.reload)
  end

  def sync_steps(campaign)
    incoming = params.permit(steps: STEP_ATTRIBUTES)[:steps] || []
    kept_ids = incoming.filter_map { |step| step[:id].presence&.to_i }
    campaign.steps.where.not(id: kept_ids).destroy_all
    incoming.each_with_index { |attributes, index| save_step(campaign, attributes, index) }
  end

  def save_step(campaign, attributes, index)
    step = attributes[:id].present? ? campaign.steps.find(attributes[:id]) : campaign.steps.new
    step.assign_attributes(attributes.except(:id, :blob_id).merge(position: index))
    attach_step_media(step, attributes[:blob_id])
    step.save!
  end

  def attach_step_media(step, blob_id)
    return step.media = nil if step.kind == 'text' && step.media.attached?
    return if blob_id.blank?

    blob = ActiveStorage::Blob.find_signed(blob_id.to_s)
    raise(ActiveRecord::RecordInvalid, step.tap { |s| s.errors.add(:media, :blank) }) if blob.nil?

    step.media = blob
  end

  def replan(campaign)
    campaign.unschedule_future!
    Whatsapp::StatusCampaigns::Planner.new(campaign.reload).plan!
  end

  def campaign_params
    params.permit(:name, :description, :color, :folder_id, :starts_on, :ends_on, :cycle_days, :time_zone, inbox_ids: [])
  end

  def summary(campaign, next_at = nil)
    campaign.slice(:id, :name, :description, :color, :status, :folder_id, :inbox_ids, :starts_on, :ends_on, :cycle_days, :time_zone)
            .merge(steps_count: campaign.steps.size, next_post_at: next_at&.iso8601, folder_name: campaign.folder&.name,
                   reposts_count: campaign.steps.sum(&:repost_count))
  end

  def detail(campaign)
    summary(campaign, campaign.posts.status_scheduled.minimum(:scheduled_at)).merge(
      steps: campaign.steps.map { |step| step_payload(step) },
      published_count: campaign.posts.where(status: %i[published partially_published]).count
    )
  end

  def step_payload(step)
    step.slice(:id, :kind, :body, :background_color, :font, :day_offset, :time_of_day, :repost_count, :repost_interval_hours)
        .merge(media: step.media.attached? ? { url: url_for(step.media), content_type: step.media.blob.content_type } : nil)
  end

  def occurrence_payload(occurrence)
    { at: occurrence.at.iso8601, step_id: occurrence.step.id, cycle: occurrence.round, repost: occurrence.repost,
      body: occurrence.step.body, kind: occurrence.step.kind }
  end
end
