class Ai::QuotaService
  DEFAULT_MONTHLY_CAP = 5_000

  def self.check!(account:)
    new(account: account).check!
  end

  def self.usage_summary(account:)
    new(account: account).usage_summary
  end

  def initialize(account:)
    @account = account
  end

  def check!
    return if cap.zero?

    used = invocations_this_month
    return if used < cap

    Rails.logger.warn("[Athenas] quota exceeded for account #{@account.id}: #{used}/#{cap}")
    raise Ai::ClaudeService::Error,
          "Limite mensal de respostas IA atingido (#{used}/#{cap}). Tente novamente no próximo mês."
  end

  def usage_summary
    { used: invocations_this_month, cap: cap, remaining: [cap - invocations_this_month, 0].max }
  end

  private

  def cap
    @cap ||= account_cap || ENV.fetch('ATHENAS_MONTHLY_INVOCATION_CAP', DEFAULT_MONTHLY_CAP).to_i
  end

  def account_cap
    value = @account.custom_attributes&.dig('athenas_monthly_cap')
    Integer(value, exception: false) if value
  end

  def invocations_this_month
    @invocations_this_month ||= @account.ai_invocations
                                        .where(created_at: Time.current.beginning_of_month..)
                                        .count
  end
end
