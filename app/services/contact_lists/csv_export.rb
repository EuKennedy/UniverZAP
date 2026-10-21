require 'csv'

# A lista em CSV: nome, telefone, situação na lista, consentimento,
# etiquetas e quando entrou/saiu (no fuso do salão).
class ContactLists::CsvExport
  def initialize(list)
    @list = list
    @zone = Broadcasts::SendWindow.default_for(list.account).zone
  end

  def to_csv
    members = @list.members.includes(:contact).order(:status, :id).to_a
    cold = Contacts::BroadcastConsent.unconsented_ids(@list.account, members.filter_map(&:contact_id)).to_set
    CSV.generate do |csv|
      csv << I18n.t('contact_lists.export.headers')
      members.each { |member| csv << row(member, cold) }
    end
  end

  private

  def row(member, cold)
    contact = member.contact
    [contact&.name || member.display_name, contact&.phone_number.presence || I18n.t('contact_lists.export.no_phone'),
     I18n.t("contact_lists.export.status.#{member.status}"),
     I18n.t("contact_lists.export.consent.#{cold.include?(member.contact_id) ? 'no' : 'yes'}"),
     contact&.label_list&.join(', '), time(member.joined_at), time(member.left_at)]
  end

  def time(value)
    value&.in_time_zone(@zone)&.strftime('%d/%m/%Y %H:%M')
  end
end
