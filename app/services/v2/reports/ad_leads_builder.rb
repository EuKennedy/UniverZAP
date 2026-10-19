# Leads per Click-to-WhatsApp ad: conversations stamped by
# Conversations::AdReferralService, grouped by ad id inside the period.
# "converted" counts the ones carrying the label the caller treats as the
# goal (e.g. agendado); without a label the column is nil, not zero.
class V2::Reports::AdLeadsBuilder
  pattr_initialize [:account!, :params!]

  AD_ID = Arel.sql("conversations.custom_attributes->>'anuncio_id'")
  COLUMNS = [
    AD_ID,
    Arel.sql("MAX(conversations.custom_attributes->>'anuncio_titulo')"),
    Arel.sql("MAX(conversations.custom_attributes->>'anuncio_url')"),
    Arel.sql('COUNT(*)'),
    Arel.sql('COUNT(conversations.first_reply_created_at)'),
    Arel.sql("COUNT(*) FILTER (WHERE conversations.status = #{Conversation.statuses[:resolved]})")
  ].freeze

  def build
    converted = converted_counts
    rows = base_scope.group(AD_ID).pluck(*COLUMNS).map do |row|
      ad_id, title, url, leads, replied, resolved = row
      { ad_id: ad_id, title: title, url: url, leads: leads, replied: replied, resolved: resolved,
        converted: converted&.fetch(ad_id, 0) }
    end
    rows.sort_by { |row| -row[:leads] }
  end

  private

  def base_scope
    account.conversations.unscope(:order)
           .where("jsonb_exists(conversations.custom_attributes, 'anuncio_id')")
           .where(created_at: range)
  end

  def range
    since = params[:since].present? ? Time.zone.at(params[:since].to_i) : 30.days.ago
    # `until` arrives in whole seconds; cover that whole second.
    till = params[:until].present? ? Time.zone.at(params[:until].to_i + 1) : Time.current
    since...till
  end

  def converted_counts
    label = params[:conversion_label].presence
    return nil if label.nil?

    base_scope.tagged_with(label, on: :labels).group(AD_ID).count
  end
end
