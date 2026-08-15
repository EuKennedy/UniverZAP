# The account's AI panel, for the Relatórios screen.
#
# Gated by ReportPolicy rather than by an administrator check of its own, on
# purpose: this renders inside Relatórios, and a section that 403s for somebody
# the product just let into that screen is a hole in a page they were invited
# to open. Whoever may see Relatórios may see what Relatórios shows.
class Api::V1::Accounts::Ai::ReportsController < Api::V1::Accounts::BaseController
  before_action :ensure_report_access

  def show
    render json: Ai::Reports::AccountOverview.new(account: Current.account, days: params[:days].to_i).perform
  end

  private

  # The policy is named, not inferred. The inherited `check_authorization`
  # derives a model from the controller name — "reports" becomes `Report` — and
  # there is no Report class in this codebase, so every request would have died
  # as a NameError long before anybody's permissions were consulted.
  def ensure_report_access
    authorize(:report, :view?)
  end
end
