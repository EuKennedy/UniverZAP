# Listas de distribuição: fotos de contatos que viram público de disparo.
# Origens: grupo do WhatsApp (extração pela WAHA, com "Atualizar a partir do
# grupo"), CSV de telefones, escolha manual e filtro por etiqueta.
class Api::V1::Accounts::ContactListsController < Api::V1::Accounts::BaseController
  COLLECTION_ACTIONS = %w[index create stats merge extract_group groups].freeze
  MEMBERS_PER_PAGE = 50

  before_action :fetch_contact_list, except: COLLECTION_ACTIONS.map(&:to_sym)
  before_action :authorize_action

  def index
    @contact_lists = policy_scope(Current.account.contact_lists).order(updated_at: :desc).to_a
    @counts = ContactLists::Summary.counts_for(@contact_lists.map(&:id))
  end

  def stats
    render json: ContactLists::Summary.for_account(Current.account)
  end

  def show
    @summary = ContactLists::Summary.for_list(@contact_list)
  end

  # Manual nasce vazia; filtro já nasce com a foto de quem tem as etiquetas.
  def create
    @contact_list = Current.account.contact_lists.create!(list_params.merge(source: creation_source))
    snapshot_filter if @contact_list.source == 'filter'
    show_list
  end

  def update
    @contact_list.update!(list_params)
    show_list
  end

  def destroy
    @contact_list.destroy!
    head :ok
  end

  def members
    scope = ContactLists::MemberQuery.new(@contact_list, filter: params[:filter], query: params[:q]).scope
    page = [params[:page].to_i, 1].max
    total = scope.count
    rows = scope.offset((page - 1) * MEMBERS_PER_PAGE).limit(MEMBERS_PER_PAGE).to_a
    cold = Contacts::BroadcastConsent.unconsented_ids(Current.account, rows.filter_map(&:contact_id)).to_set
    render json: { meta: { total: total, page: page, per_page: MEMBERS_PER_PAGE }, payload: rows.map { |member| member_payload(member, cold) } }
  end

  def add_members
    added = ContactLists::MemberService.new(@contact_list).add(params[:contact_ids])
    render json: { added: added, members_count: @contact_list.members_count }
  end

  def remove_members
    removed = ContactLists::MemberService.new(@contact_list).remove_members(params[:member_ids])
    render json: { removed: removed, members_count: @contact_list.members_count }
  end

  def import_csv
    content = params[:file].respond_to?(:read) ? params[:file].read : params[:content]
    cold = ActiveModel::Type::Boolean.new.cast(params[:cold])
    render json: ContactLists::CsvImportService.new(@contact_list, content, cold: cold).perform.merge(members_count: @contact_list.members_count)
  end

  def deduplicate
    removed = ContactLists::DeduplicateService.new(@contact_list).perform
    render json: { removed: removed, members_count: @contact_list.members_count }
  end

  def export
    filename = "lista-#{@contact_list.name.parameterize}-#{Time.current.strftime('%Y%m%d')}.csv"
    send_data ContactLists::CsvExport.new(@contact_list).to_csv, type: 'text/csv; charset=utf-8', filename: filename
  end

  def merge
    @contact_list = ContactLists::MergeService.new(account: Current.account, list_ids: params[:list_ids], name: params[:name],
                                                   description: params[:description]).perform
    show_list
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Grupos que dá para extrair: conversas de grupo em caixas ligadas à WAHA.
  def groups
    render json: { payload: ContactLists::GroupCatalog.new(Current.account).to_a }
  end

  # Cria a lista do grupo (ou reaproveita a que já existe) e busca os
  # participantes em segundo plano; a tela acompanha pelo status.
  def extract_group
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    return render_error(I18n.t('contact_lists.errors.not_a_group')) unless conversation.is_group

    @contact_list = ContactLists::GroupCatalog.new(Current.account).list_for!(conversation)
    start_extraction
  rescue Whatsapp::WahaInboxResolver::NotWahaInboxError => e
    render_error(e.message)
  end

  def refresh
    return render_error(I18n.t('contact_lists.errors.not_a_group_list')) unless @contact_list.group?

    start_extraction
  end

  private

  def start_extraction
    return render_error(I18n.t('contact_lists.errors.importing')) if @contact_list.importing? && @contact_list.updated_at > 10.minutes.ago

    @contact_list.update!(status: 'importing', last_error: nil)
    ContactLists::GroupExtractionJob.perform_later(@contact_list.id)
    show_list
  end

  def show_list
    @summary = ContactLists::Summary.for_list(@contact_list.reload)
    render :show
  end

  def snapshot_filter
    titles = Current.account.labels.where(id: Array(params.dig(:contact_list, :label_ids)).map(&:to_i)).pluck(:title)
    @contact_list.update!(metadata: { 'filter' => { 'labels' => titles } })
    ids = titles.any? ? Current.account.contacts.tagged_with(titles, any: true).pluck(:id) : []
    ContactLists::MemberService.new(@contact_list).add(ids)
  end

  def creation_source
    source = params.dig(:contact_list, :source).to_s
    %w[csv filter].include?(source) ? source : 'manual'
  end

  def member_payload(member, cold)
    contact = member.contact
    {
      id: member.id, contact_id: member.contact_id, name: contact&.name.presence || member.display_name,
      phone: contact&.phone_number.presence, thumbnail: contact&.avatar_url, status: member.status, role: member.role,
      joined_at: member.joined_at&.to_i, left_at: member.left_at&.to_i, cold: cold.include?(member.contact_id),
      is_new: ContactLists::MemberQuery.new_member?(@contact_list, member)
    }
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def list_params
    params.require(:contact_list).permit(:name, :description)
  end

  def fetch_contact_list
    @contact_list = Current.account.contact_lists.find(params[:id])
  end

  def authorize_action
    authorize(COLLECTION_ACTIONS.include?(action_name) ? ContactList : @contact_list)
  end
end
