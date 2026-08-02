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
      "[Athenas] quota exhausted account=#{error.account.id} reason=#{error.reason} " \
      "attempted=#{error.attempted_cents} balance=#{error.balance_cents}"
    )
    default_msg, i18n_key = if error.reason == 'daily_cap'
                              ['Limite diário de IA atingido. Tente novamente amanhã ou aumente o teto.',
                               'errors.athenas.daily_cap_exceeded']
                            else
                              ['Os créditos de IA acabaram. Recarregue para continuar atendendo.',
                               'errors.athenas.quota_exhausted']
                            end
    render json: {
      error: 'athenas_quota_exhausted',
      code: 'athenas_quota_exhausted',
      reason: error.reason,
      message: I18n.t(i18n_key, default: default_msg),
      balance_cents_brl: error.balance_cents,
      attempted_cents_brl: error.attempted_cents
    }, status: :payment_required
  end
end
