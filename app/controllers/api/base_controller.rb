class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  # Univercart subscription gating only makes sense for authenticated
  # dashboard users — never for SuperAdmin, devise mail templates, public
  # widget endpoints, etc. The concern is included here (instead of in
  # ApplicationController) so its `if: :user_signed_in?` callback can't
  # accidentally trigger `current_user` on controllers outside the API.
  include UnivercartSubscriptionGuard
  respond_to :json
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def check_authorization(model = nil)
    model ||= controller_name.classify.constantize

    authorize(model)
  end

  def check_admin_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
