# Leads per Click-to-WhatsApp ad: conversations stamped by
# Conversations::AdReferralService, grouped by ad id inside the period — or by
# assignee when `group_by: 'agent'`, to see who turns ad leads into bookings.
# "converted" counts the ones carrying the label the caller treats as the
# goal (e.g. agendado); without a label the column is nil, not zero.
class V2::Reports::AdLeadsBuilder
  include V2::Reports::DashboardScopes

  pattr_initialize [:account!, :params!]

  AD_ID = Arel.sql("conversations.custom_attributes->>'anuncio_id'")
  AD_COLUMNS = [
    Arel.sql("MAX(conversations.custom_attributes->>'anuncio_titulo')"),
    Arel.sql("MAX(conversations.custom_attributes->>'anuncio_url')")
  ].freeze
  COUNTS = [Arel.sql('COUNT(*)'), REPLIED, RESOLVED].freeze

  def build
    rows = params[:group_by] == 'agent' ? agent_rows : ad_rows
    rows.sort_by { |row| -row[:leads] }
  end

  private

  def base_scope
    period_scope.where("jsonb_exists(conversations.custom_attributes, 'anuncio_id')")
  end

  def ad_rows
    converted = converted_by(base_scope, AD_ID)
    base_scope.group(AD_ID).pluck(AD_ID, *AD_COLUMNS, *COUNTS).map do |ad_id, title, url, *counts|
      { ad_id: ad_id, title: title, url: url, **metrics(counts, converted, ad_id) }
    end
  end

  def agent_rows
    converted = converted_by(base_scope, :assignee_id)
    names = account.users.pluck(:id, :name).to_h
    base_scope.group(:assignee_id).pluck(:assignee_id, *COUNTS).map do |agent_id, *counts|
      { agent_id: agent_id, title: names[agent_id], **metrics(counts, converted, agent_id) }
    end
  end

  def metrics(counts, converted, key)
    leads, replied, resolved = counts
    { leads: leads, replied: replied, resolved: resolved, converted: converted&.fetch(key, 0) }
  end
end
