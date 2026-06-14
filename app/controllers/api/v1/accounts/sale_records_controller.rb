class Api::V1::Accounts::SaleRecordsController < Api::V1::Accounts::BaseController
  before_action :authorize_action

  def index
    @sale_records = Current.account.sale_records
                           .where(contact_id: params[:contact_id])
                           .order(recorded_at: :desc)
                           .limit(50)
  end

  def create
    @sale_record = Current.account.sale_records.new(
      contact_id: params[:contact_id],
      amount: params[:amount],
      user_id: Current.user.id,
      recorded_at: Time.current
    )
    @sale_record.save!
    render json: sale_record_payload, status: :created
  end

  private

  def authorize_action
    authorize(SaleRecord)
  end

  def sale_record_payload
    {
      id: @sale_record.id,
      contact_id: @sale_record.contact_id,
      user_id: @sale_record.user_id,
      amount: @sale_record.amount,
      recorded_at: @sale_record.recorded_at,
      contact_total: @sale_record.contact.additional_attributes['valor_em_compras']
    }
  end
end
