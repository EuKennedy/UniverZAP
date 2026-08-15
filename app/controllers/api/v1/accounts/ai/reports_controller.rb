# The account's AI panel, for the Relatórios screen.
#
# Gated by ReportPolicy rather than by an administrator check of its own, on
# purpose: this renders inside Relatórios, and a section that 403s for somebody
# the product just let into that screen is a hole in a page they were invited
# to open. Whoever may see Relatórios may see what Relatórios shows.
class Api::V1::Accounts::Ai::ReportsController < Api::V1::Accounts::BaseController
  # `controller_name` is "reports", so this resolves to the same Report policy
  # the conversation reports use. Kept implicit for exactly that reason: the two
  # screens must never drift into different answers about who may read them.
  before_action :check_authorization

  def show
    render json: Ai::Reports::AccountOverview.new(account: Current.account, days: params[:days].to_i).perform
  end
end
