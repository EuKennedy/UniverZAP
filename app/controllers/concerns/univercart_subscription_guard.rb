module UnivercartSubscriptionGuard
  extend ActiveSupport::Concern

  included do
    before_action :check_univercart_status, if: :user_signed_in?
  end

  private

  # Bloqueia users com subscription suspended/cancelled. Legacy Chatwoot
  # users sem UnivercartSubscription passam direto (nil sub).
  def check_univercart_status
    sub = UnivercartSubscription.find_by(user_id: current_user.id)
    return if sub.nil?
    return if sub.status == 'active'

    message = univercart_block_message(sub.status)
    respond_to do |format|
      format.json do
        render json: { error: { code: "subscription_#{sub.status}", message: message } }, status: :payment_required
      end
      format.html do
        sign_out(current_user)
        redirect_to '/users/sign_in', alert: message
      end
      format.any { head :payment_required }
    end
  end

  def univercart_block_message(status)
    case status
    when 'suspended' then 'Pagamento pendente. Atualize seu cartão para reativar a conta.'
    when 'cancelled' then 'Assinatura cancelada. Reative para voltar a acessar.'
    else 'Acesso bloqueado pela cobrança.'
    end
  end
end
