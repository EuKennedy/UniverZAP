# Os filtros do histórico de status: busca no texto, grupo de status, tipo,
# conexão e "agendados até" (que alimenta a agenda da semana).
class Whatsapp::StatusPosts::Filter
  # Os grupos do filtro da tela. "Enviados" junta tudo que já foi tentado.
  STATUS_GROUPS = {
    'draft' => %i[draft],
    'scheduled' => %i[scheduled],
    'sent' => %i[publishing published partially_published failed],
    'failed' => %i[partially_published failed]
  }.freeze

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
    scope = scope.where(scheduled_at: ..Time.zone.parse(@params[:until].to_s)) if @params[:until].present?
    @params[:status] == 'scheduled' ? scope.order(:scheduled_at) : scope.order(created_at: :desc)
  end

  private

  def by_status(scope)
    group = STATUS_GROUPS[@params[:status].to_s]
    group ? scope.where(status: group) : scope
  end

  def search(scope)
    term = @params[:q].to_s.strip
    return scope if term.blank?

    scope.where('body ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
  end
end
