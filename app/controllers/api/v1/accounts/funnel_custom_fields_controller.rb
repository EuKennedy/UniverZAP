class Api::V1::Accounts::FunnelCustomFieldsController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel
  before_action :fetch_field, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @fields = @funnel.custom_fields.ordered
  end

  def show; end

  def create
    @field = @funnel.custom_fields.create!(permitted_params)
  end

  def update
    @field.update!(permitted_params)
  end

  def destroy
    @field.destroy!
    head :ok
  end

  def reorder
    ids = Array(params[:ordered_ids]).map(&:to_i)
    fields_by_id = @funnel.custom_fields.where(id: ids).index_by(&:id)
    FunnelCustomField.transaction do
      ids.each_with_index do |id, index|
        fields_by_id[id]&.update!(position: index + 1)
      end
    end
    head :ok
  end

  private

  def fetch_funnel
    @funnel = Current.account.funnels.find(params[:funnel_id])
    authorize(@funnel, :show?)
  end

  def fetch_field
    @field = @funnel.custom_fields.find(params[:id])
  end

  def permitted_params
    base = params.require(:funnel_custom_field).permit(
      :name, :field_type, :position, :required
    )
    base.merge(options: options_payload)
  end

  def options_payload
    raw_options = params.dig(:funnel_custom_field, :options)
    return {} if raw_options.blank?

    raw_options.respond_to?(:to_unsafe_h) ? raw_options.to_unsafe_h : raw_options
  end
end
