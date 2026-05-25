class AddWipLimitToFunnelStages < ActiveRecord::Migration[7.1]
  def change
    add_column :funnel_stages, :wip_limit, :integer
    # Soft cap only — we never block writes on the DB, just surface a warning
    # in the column header when the count crosses the limit.
  end
end
