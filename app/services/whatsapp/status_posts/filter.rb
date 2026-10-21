# Os filtros do histórico de status: busca no texto, grupo de status, tipo,
# conexão, campanha, pasta e período (que alimentam a agenda e o calendário).
class Whatsapp::StatusPosts::Filter
  # Os grupos do filtro da tela. "Enviados" junta tudo que já foi tentado.
  STATUS_GROUPS = {
    'draft' => %i[draft],
    'scheduled' => %i[scheduled],
    'sent' => %i[publishing published partially_published failed],
    'failed' => %i[partially_published failed]
  }.freeze

  # O dia em que o status aparece no calendário: quando vai sair, quando saiu
  # ou, para rascunho, quando foi escrito.
  DAY_SQL = 'COALESCE(whatsapp_status_posts.scheduled_at, whatsapp_status_posts.published_at, whatsapp_status_posts.created_at)'.freeze

  def initialize(scope, params)
    @scope = scope
    @params = params
  end

  # Agendados em ordem de saída (o próximo primeiro); o resto do mais novo
  # para o mais antigo, que é como se lê um histórico.
  def results
    scope = by_status(@scope)
    scope = scope.where(kind: @params[:kind]) if WhatsappStatusPost::KINDS.include?(@params[:kind])
    scope = scope.where('inbox_ids @> ?', [@params[:inbox_id].to_i].to_json) if @params[:inbox_id].present?
    scope = search(scope)
    scope = by_campaign(scope)
    scope = by_period(scope)
    return scope.order(Arel.sql("#{DAY_SQL} ASC")) if @params[:from].present?

    @params[:status] == 'scheduled' ? scope.order(:scheduled_at) : scope.order(created_at: :desc)
  end

  private

  def by_status(scope)
    group = STATUS_GROUPS[@params[:status].to_s]
    group ? scope.where(status: group) : scope
  end

  def by_campaign(scope)
    scope = scope.where(campaign_id: @params[:campaign_id]) if @params[:campaign_id].present?
    return scope if @params[:folder_id].blank?

    scope.where(campaign_id: WhatsappStatusCampaign.where(folder_id: @params[:folder_id]).select(:id))
  end

  # `until` sozinho é a agenda da semana (agendados até); `from` + `until` é
  # o mês do calendário, contando o dia em que cada status aparece.
  def by_period(scope)
    upto = parse(@params[:until])
    from = parse(@params[:from])
    return scope.where(scheduled_at: ..upto) if upto && from.nil?
    return scope unless from && upto

    scope.where("#{DAY_SQL} BETWEEN ? AND ?", from, upto)
  end

  def parse(value)
    Time.zone.parse(value.to_s) if value.present?
  end

  def search(scope)
    term = @params[:q].to_s.strip
    return scope if term.blank?

    scope.where('body ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
  end
end
