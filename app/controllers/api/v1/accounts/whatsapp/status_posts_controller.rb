# Status do WhatsApp escritos no painel: rascunhos, agendamentos, publicação
# em uma ou várias conexões e o histórico de cada entrega.
#
# Publicar nunca acontece dentro do request: o post vira `publishing` e o
# PublishJob fala com a WAHA. Assim um vídeo pesado ou cinco conexões não
# seguram a tela, e o resultado de cada número aparece no histórico.
class Api::V1::Accounts::Whatsapp::StatusPostsController < Api::V1::Accounts::BaseController
  STATUS_BY_INTENT = { 'draft' => :draft, 'schedule' => :scheduled, 'publish' => :publishing }.freeze
  PER_PAGE = 20

  before_action :ensure_administrator
  before_action :fetch_post, only: [:update, :destroy, :publish, :retry]
  before_action :ensure_editable, only: [:update, :destroy, :publish]

  def index
    posts = Current.account.whatsapp_status_posts.includes(:deliveries, media_attachment: :blob)
                   .order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    render json: { payload: posts.map { |post| payload(post) }, meta: { has_more: posts.next_page.present? } }
  end

  def create
    post = Current.account.whatsapp_status_posts.new(user: current_user)
    save_with_intent(post)
  end

  def update
    save_with_intent(@post)
  end

  # Rascunho e agendado podem ser apagados: é o "cancelar agendamento". O que
  # já foi publicado fica, porque o histórico é a prova do que foi ao ar.
  def destroy
    @post.destroy!
    head :ok
  end

  def publish
    @post.update!(status: :publishing, scheduled_at: nil)
    enqueue(@post)
  end

  # Reenvia só o que falhou. O que já saiu não é tocado, para nenhum contato
  # ver o mesmo status duas vezes.
  def retry
    failed = @post.deliveries.status_failed
    return render_unprocessable('inbox.whatsapp.waha.nothing_to_retry') if failed.none?

    @post.with_lock do
      failed.find_each { |delivery| delivery.update!(status: :pending, error_message: nil) }
      @post.update!(status: :publishing)
    end
    enqueue(@post)
  end

  def suggest
    text = Whatsapp::StatusPosts::SuggestionService.new(
      account: Current.account, prompt: params[:prompt], current_text: params[:body], kind: params[:kind]
    ).perform
    render json: { text: text }
  rescue Ai::ClaudeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_administrator
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_post
    @post = Current.account.whatsapp_status_posts.find(params[:id])
  end

  def ensure_editable
    render_unprocessable('inbox.whatsapp.waha.status_not_editable') unless @post.editable?
  end

  def save_with_intent(post)
    intent = params[:intent].to_s
    return render_unprocessable('inbox.whatsapp.waha.invalid_intent') unless STATUS_BY_INTENT.key?(intent)

    blob = uploaded_blob
    return render_unprocessable('inbox.whatsapp.waha.media_not_found') if blob == :missing

    post.assign_attributes(post_params.merge(status: STATUS_BY_INTENT[intent]))
    post.scheduled_at = nil unless post.status_scheduled?
    attach_media(post, blob)
    post.save!
    post.status_publishing? ? enqueue(post) : render(json: payload(post))
  end

  # nil quando o request não trouxe arquivo; :missing quando trouxe um que não
  # existe, para a tela pedir o upload de novo em vez de salvar sem mídia.
  def uploaded_blob
    return if params[:blob_id].blank?

    ActiveStorage::Blob.find_signed(params[:blob_id].to_s) || :missing
  end

  # A mídia chega como signed_id do upload direto que o painel já faz. Sem
  # blob_id no request, um rascunho editado mantém o arquivo que já tinha.
  # Atribuir em vez de `attach` deixa a troca para o `save!`, junto com o resto
  # do post: num registro já salvo, `attach` gravaria antes da validação.
  def attach_media(post, blob)
    return post.media = nil if post.kind == 'text' && post.media.attached?

    post.media = blob if blob
  end

  def post_params
    permitted = params.permit(:kind, :body, :background_color, :font, :scheduled_at, inbox_ids: [])
    permitted[:body] = permitted[:body].to_s.strip if permitted.key?(:body)
    permitted
  end

  def enqueue(post)
    Whatsapp::StatusPosts::PublishJob.perform_later(post.id)
    render json: payload(post.reload)
  end

  def payload(post)
    {
      id: post.id,
      kind: post.kind,
      body: post.body,
      background_color: post.background_color,
      font: post.font,
      status: post.status,
      inbox_ids: post.inbox_ids,
      scheduled_at: post.scheduled_at&.iso8601,
      published_at: post.published_at&.iso8601,
      created_at: post.created_at.iso8601,
      media: media_payload(post),
      deliveries: post.deliveries.map { |delivery| delivery_payload(delivery) }
    }
  end

  def media_payload(post)
    return unless post.media.attached?

    blob = post.media.blob
    { url: url_for(post.media), content_type: blob.content_type, filename: blob.filename.to_s }
  end

  def delivery_payload(delivery)
    delivery.slice(:id, :inbox_id, :inbox_name, :status, :error_message).merge(sent_at: delivery.sent_at&.iso8601)
  end

  def render_unprocessable(key)
    render json: { error: I18n.t(key) }, status: :unprocessable_entity
  end
end
