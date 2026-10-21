# Lista de destinatários do relatório de um disparo, com filtro por resultado
# e busca por nome ou telefone — a mesma régua das contagens do topo, para o
# número do filtro "Falhas" bater com a lista que ele mostra. Também vira o
# CSV que o dono baixa para conferir ou retrabalhar quem não recebeu.
require 'csv'

class Broadcasts::RecipientReport
  FILTERS = %w[all sent delivered read replied failed skipped pending].freeze
  SENT = %w[sent delivered read].freeze

  def initialize(broadcast, filter: 'all', query: nil)
    @broadcast = broadcast
    @filter = FILTERS.include?(filter.to_s) ? filter.to_s : 'all'
    @query = query.to_s.strip
  end

  def scope
    rel = @broadcast.broadcast_recipients.left_joins(:contact, :message).includes(:contact, :message)
    rel = filtered(rel)
    rel = searched(rel) if @query.present?
    rel.order(Arel.sql('broadcast_recipients.sent_at DESC NULLS LAST'), id: :desc)
  end

  def to_csv
    CSV.generate do |csv|
      csv << I18n.t('broadcasts.report.csv_headers').values
      scope.find_each(batch_size: 500) { |recipient| csv << row(recipient) }
    end
  end

  private

  def filtered(rel)
    case @filter
    when 'sent' then rel.where(status: SENT)
    when 'delivered' then rel.where(status: SENT, messages: { status: message_statuses(%w[delivered read]) })
    when 'read' then rel.where(status: SENT, messages: { status: message_statuses(%w[read]) })
    when 'replied' then rel.where.not(replied_at: nil)
    when 'failed' then rel.where(status: :failed).or(rel.where(status: SENT, messages: { status: message_statuses(%w[failed]) }))
    when 'skipped', 'pending' then rel.where(status: @filter)
    else rel
    end
  end

  # A condição vai na tabela `messages` do join, onde o enum não é traduzido.
  def message_statuses(names)
    Message.statuses.values_at(*names)
  end

  def searched(rel)
    like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    digits = @query.gsub(/\D/, '')
    condition = rel.where('contacts.name ILIKE ?', like)
    digits.length >= 4 ? condition.or(rel.where('contacts.phone_number LIKE ?', "%#{digits}%")) : condition
  end

  def row(recipient)
    contact = recipient.contact
    [
      contact&.name, contact&.phone_number,
      I18n.t("broadcasts.report.result.#{result_of(recipient)}"),
      recipient.skip_reason && I18n.t("broadcasts.report.skip_reason.#{recipient.skip_reason}", default: recipient.skip_reason),
      recipient.error || recipient.message&.content_attributes&.dig('external_error'),
      local(recipient.sent_at), local(recipient.replied_at)
    ]
  end

  def result_of(recipient)
    return 'replied' if recipient.replied_at.present?
    return recipient.status unless SENT.include?(recipient.status)

    %w[delivered read failed].include?(recipient.message&.status) ? recipient.message.status : 'sent'
  end

  def local(time)
    time&.in_time_zone(Broadcasts::SendWindow.default_for(@broadcast.account).zone)&.strftime('%d/%m/%Y %H:%M')
  end
end
