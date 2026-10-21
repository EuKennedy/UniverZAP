# Membros de uma lista para a tela: busca por nome/telefone e os filtros
# da tabela (ativos, saíram, sem telefone, nunca falaram, novos).
class ContactLists::MemberQuery
  FILTERS = %w[all active left no_phone cold new].freeze

  # Entrou na última atualização a partir do grupo (não na primeira extração).
  def self.new_member?(list, member)
    return false unless list.metadata.dig('last_run', 'joined').to_i.positive? && member.joined_at && list.refreshed_at

    member.status_active? && member.joined_at >= list.refreshed_at - 1.second
  end

  def initialize(list, filter:, query:)
    @list = list
    @filter = FILTERS.include?(filter) ? filter : 'all'
    @query = query.to_s.strip
  end

  def scope
    scope = @list.members.left_joins(:contact).includes(:contact).order(:status,
                                                                        Arel.sql('LOWER(COALESCE(contacts.name, contact_list_members.display_name))'))
    scope = search(scope) if @query.present?
    filtered(scope)
  end

  private

  def search(scope)
    like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    digits = @query.gsub(/\D/, '')
    clause = scope.where('contacts.name ILIKE :like OR contact_list_members.display_name ILIKE :like', like: like)
    digits.length >= 4 ? clause.or(scope.where('contacts.phone_number LIKE ?', "%#{digits}%")) : clause
  end

  def filtered(scope)
    case @filter
    when 'active' then scope.status_active
    when 'left' then scope.status_left
    when 'no_phone' then scope.status_active.where(contacts: { phone_number: [nil, ''] })
    when 'cold' then scope.where(contact_id: Contacts::BroadcastConsent.unconsented_ids(@list.account, @list.members.pluck(:contact_id).compact))
    when 'new' then new_scope(scope)
    else scope
    end
  end

  def new_scope(scope)
    return scope.none unless @list.metadata.dig('last_run', 'joined').to_i.positive? && @list.refreshed_at

    scope.status_active.where(contact_list_members: { joined_at: (@list.refreshed_at - 1.second).. })
  end
end
