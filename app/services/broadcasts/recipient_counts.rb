# Contagens por disparo em duas queries agrupadas, para a lista não fazer
# cinco COUNT por campanha.
class Broadcasts::RecipientCounts
  SENT = %w[sent delivered read].freeze

  def self.for(broadcast_ids)
    return {} if broadcast_ids.empty?

    scope = BroadcastRecipient.where(broadcast_id: broadcast_ids)
    by_status = scope.group(:broadcast_id, :status).count
    replied = scope.where.not(replied_at: nil).group(:broadcast_id).count
    broadcast_ids.index_with { |id| build(by_status, replied, id) }
  end

  def self.build(by_status, replied, id)
    statuses = by_status.select { |(broadcast_id, _), _| broadcast_id == id }.transform_keys(&:last)
    {
      recipients: statuses.values.sum, sent: statuses.slice(*SENT).values.sum, failed: statuses['failed'].to_i,
      skipped: statuses['skipped'].to_i, pending: statuses['pending'].to_i, replied: replied[id].to_i
    }
  end
end
