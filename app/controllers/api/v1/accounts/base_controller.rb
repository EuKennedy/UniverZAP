class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  around_action :switch_locale_using_account_locale

  # Athenas billing — every BRL-credit miss in any downstream service
  # (rewrite, suggest, summarize, autopilot, chat threads, …) bubbles
  # up here so the dashboard sees HTTP 402 with a structured payload.
  # The frontend's axios interceptor opens the top-up modal when it
  # spots this error code instead of surfacing a raw stacktrace.
  rescue_from Ai::CreditLedger::QuotaExhaustedError do |error|
    Rails.logger.warn(
      "[Athenas] quota exhausted account=#{error.account.id} " \
      "attempted=#{error.attempted_cents} balance=#{error.balance_cents}"
    )
    render json: {
      error: 'athenas_quota_exhausted',
      code: 'athenas_quota_exhausted',
      message: I18n.t(
        'errors.athenas.quota_exhausted',
        default: 'Os créditos Athenas acabaram. Recarregue para continuar atendendo.'
      ),
      balance_cents_brl: error.balance_cents,
      attempted_cents_brl: error.attempted_cents
    }, status: :payment_required
  end
end
