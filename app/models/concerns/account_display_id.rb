# Assigns a sequential, per-account `display_id` to records on create.
#
# `maximum + 1` alone is racy: two concurrent inserts read the same maximum
# and collide on the `[account_id, display_id]` unique index. We serialise
# the computation with a transaction-scoped Postgres advisory lock keyed by
# (table, account). The lock is released automatically at commit/rollback,
# which also covers the window between the callback and the actual INSERT.
module AccountDisplayId
  extend ActiveSupport::Concern

  included do
    before_create :assign_display_id
  end

  private

  def assign_display_id
    return if display_id.present?

    lock_sql = self.class.sanitize_sql_array(
      ['SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', "#{self.class.table_name}_display_id_#{account_id}"]
    )
    self.class.connection.execute(lock_sql)
    self.display_id = (self.class.where(account_id: account_id).maximum(:display_id) || 0) + 1
  end
end
