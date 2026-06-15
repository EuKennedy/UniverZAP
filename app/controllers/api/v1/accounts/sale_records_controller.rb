class Api::V1::Accounts::SaleRecordsController < Api::V1::Accounts::BaseController
  before_action :authorize_action

  def index
    @sale_records = Current.account.sale_records
                           .where(contact_id: params[:contact_id])
                           .order(recorded_at: :desc)
                           .limit(50)
  end

  def create
    paid_at = params[:paid_at].presence
    @sale_record = Current.account.sale_records.new(
      contact_id: params[:contact_id].presence,
      amount: params[:amount],
      category: params[:category].presence || 'sales',
      order_number: params[:order_number].presence,
      paid_at: paid_at,
      user_id: target_user_id,
      recorded_at: paid_at || Time.current
    )
    @sale_record.save!
    render json: sale_record_payload, status: :created
  end

  private

  def authorize_action
    authorize(SaleRecord)
  end

  # Agents register against themselves. Only admins may attribute a record to a
  # different agent (used by the Metas panel's per-card register action).
  def target_user_id
    requested = params[:user_id].presence
    return Current.user.id if requested.blank?

    Current.account_user.administrator? ? requested : Current.user.id
  end

  def sale_record_payload
    {
      id: @sale_record.id,
      contact_id: @sale_record.contact_id,
      user_id: @sale_record.user_id,
      amount: @sale_record.amount,
      category: @sale_record.category,
      order_number: @sale_record.order_number,
      paid_at: @sale_record.paid_at,
      recorded_at: @sale_record.recorded_at,
      contact_total: @sale_record.contact&.additional_attributes&.dig('valor_em_compras')
    }
  end
end
