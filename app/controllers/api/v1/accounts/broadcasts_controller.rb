class Api::V1::Accounts::BroadcastsController < Api::V1::Accounts::BaseController
  before_action :fetch_broadcast, except: [:index, :create, :templates, :variations, :stats]
  before_action :authorize_action

  def index
    @broadcasts = policy_scope(Current.account.broadcasts).order(created_at: :desc).to_a
    @counts = Broadcasts::RecipientCounts.for(@broadcasts.map(&:id))
  end

  # Números do topo da página + uso de hoje por conexão contra o teto.
  def stats
    render json: Broadcasts::Stats.new(Current.account).to_h
  end

  # Cópia em rascunho: mesma mensagem, público e proteção, sem destinatários.
  # Relançar a campanha antiga não alcança quem já recebeu; duplicar é como
  # o operador reaproveita um texto aprovado para outra leva.
  def duplicate
    copy = @broadcast.dup
    copy.assign_attributes(name: I18n.t('broadcasts.copy_name', name: @broadcast.name), status: :draft, scheduled_at: nil, pause_reason: nil)
    copy.save!
    @broadcast = copy
    render :show
  end

  def show; end

  def create
    @broadcast = Current.account.broadcasts.new(permitted_params)
    @broadcast.save!
    render :show
  end

  def update
    @broadcast.update!(permitted_params)
    render :show
  end

  def destroy
    @broadcast.destroy!
    head :ok
  end

  # Flip the broadcast live and kick off the adaptive dispatch loop. With a
  # future scheduled_at it waits as `scheduled` and the job starts it then.
  def launch
    if @broadcast.scheduled_at.present? && @broadcast.scheduled_at > Time.current
      @broadcast.update!(status: :scheduled, pause_reason: nil)
      Broadcasts::DispatchJob.set(wait_until: @broadcast.scheduled_at).perform_later(@broadcast.id)
    else
      @broadcast.update!(status: :running, pause_reason: nil)
      Broadcasts::DispatchJob.perform_later(@broadcast.id)
    end
    render :show
  end

  def pause
    @broadcast.update!(status: :paused, pause_reason: 'manual')
    render :show
  end

  # Who would receive it, who the guard leaves out, the exact text of a
  # sample and how long the cadence takes — before anything is sent.
  # `new_count` is who a relaunch would actually reach: contacts already
  # recipients are never sent again.
  def audience_preview
    render json: Broadcasts::AudiencePreviewService.new(@broadcast).perform
  end

  # 2–3 versões do texto pela IA da conta, para o operador revisar.
  def variations
    render json: { variations: Broadcasts::VariationSuggestionService.new(account: Current.account, text: params[:text]).perform }
  rescue Ai::ClaudeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Approved Meta templates for a Cloud API inbox, for the official-mode picker.
  # Reads the channel's cached copy, which the scheduler refreshes every few
  # hours. `refresh=true` syncs from Meta first: without it a template approved
  # minutes ago stayed invisible here, while the inbox settings screen — which
  # asks Meta live — already listed it.
  def templates
    channel = Current.account.inboxes.find(params[:inbox_id]).channel
    channel.sync_templates if refresh_templates?(channel)
    list = channel.respond_to?(:message_templates) ? Array(channel.message_templates) : []
    render json: { templates: list.select { |tpl| tpl['status']&.downcase == 'approved' } }
  end

  # Per-recipient progress log for the live tracking popup. Returns the rolling
  # counts plus the most-recent recipients with their delivery status.
  def recipients
    list = @broadcast.broadcast_recipients.includes(:contact, :message)
                     .order(Arel.sql('sent_at DESC NULLS LAST'), id: :desc).limit(200)
    render json: {
      status: @broadcast.status,
      pause_reason: @broadcast.pause_reason,
      counts: recipient_counts,
      recipients: list.map { |recipient| recipient_payload(recipient) }
    }
  end

  private

  # Report: delivery and read come from the WhatsApp ack on the message the
  # recipient got (Message#status), replies from ScheduledMessageListener.
  def recipient_counts
    rel = @broadcast.broadcast_recipients
    sent = rel.where(status: %i[sent delivered read])
    acks = Message.unscope(:order).where(id: sent.select(:message_id)).group(:status).count
    {
      total: rel.count, sent: sent.count, pending: rel.status_pending.count,
      replied: sent.where.not(replied_at: nil).count,
      failed: rel.status_failed.count + acks['failed'].to_i
    }.merge(delivery_counts(acks), skipped_counts(rel))
  end

  def delivery_counts(acks)
    { delivered: acks.slice('delivered', 'read').values.sum, read: acks['read'].to_i }
  end

  def skipped_counts(rel)
    { skipped: rel.status_skipped.count, skipped_by_reason: rel.status_skipped.group(:skip_reason).count }
  end

  def recipient_payload(recipient)
    {
      id: recipient.id,
      name: recipient.contact&.name,
      phone: recipient.contact&.phone_number,
      status: recipient.status,
      delivery: recipient.message&.status,
      sent_at: recipient.sent_at&.to_i,
      replied_at: recipient.replied_at&.to_i,
      send_after: recipient.send_after&.to_i,
      skip_reason: recipient.skip_reason,
      error: recipient.error
    }
  end

  def refresh_templates?(channel)
    ActiveModel::Type::Boolean.new.cast(params[:refresh]) && channel.respond_to?(:sync_templates)
  end

  def fetch_broadcast
    @broadcast = Current.account.broadcasts.find(params[:id])
  end

  def authorize_action
    case action_name
    when 'index', 'create', 'templates', 'variations', 'stats'
      authorize(Broadcast)
    else
      authorize(@broadcast)
    end
  end

  def permitted_params
    params.require(:broadcast).permit(
      :name, :inbox_id, :mode, :scheduled_at,
      message: {}, audience: {}, throttle: {}
    )
  end
end
