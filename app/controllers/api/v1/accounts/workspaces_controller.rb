# UniverZAP: the identity of a workspace — cover, logo, cover theme and the
# service vertical of its activity. Only admins change it; the result shows up
# for everyone in the account switcher. Choosing a vertical runs the same
# applier as Super Admin: it only creates the missing statuses, attributes and
# automations, never removes what the account already has.
class Api::V1::Accounts::WorkspacesController < Api::V1::Accounts::BaseController
  ATTACHMENTS = %w[cover logo].freeze

  before_action :authorize_change, only: [:update, :destroy]

  def show
    render json: {
      vertical: Current.account.custom_attributes['vertical_template'],
      verticals: Vertical.order(:name).map { |vertical| vertical.slice(:key, :name, :description) }
    }
  end

  def update
    @account = Current.account
    assign_look
    @account.save!
    VerticalTemplates::Applier.new(account: @account, vertical: params[:vertical]).perform! if params[:vertical].present?
    render 'api/v1/accounts/show', format: :json
  end

  def destroy
    @account = Current.account
    attachment = params.require(:attachment)
    raise ActionController::BadRequest, 'Unknown attachment' unless ATTACHMENTS.include?(attachment)

    @account.public_send(attachment).purge
    render 'api/v1/accounts/show', format: :json
  end

  private

  def assign_look
    ATTACHMENTS.each { |name| @account.public_send(name).attach(params[name]) if params[name].present? }
    @account.cover_theme = params[:cover_theme].presence if params.key?(:cover_theme)
  end

  def authorize_change
    authorize Current.account, :update?
  end
end
