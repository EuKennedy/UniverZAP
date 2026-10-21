# Mensagens agendadas de UMA conversa. Quem pode ver a conversa pode agendar,
# editar e cancelar nela (mesma regra do ConversationPolicy#show?).
class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  # Fora o que está pendente, o indicador mostra as últimas que saíram, falharam
  # ou foram canceladas, para o atendente entender o que aconteceu.
  RECENT_LIMIT = 5

  before_action :fetch_conversation, only: [:index, :create, :best_time]
  before_action :fetch_scheduled_message, only: [:update, :destroy]

  def index
    scope = @conversation.scheduled_messages.includes(:created_by)
    @scheduled_messages = scope.pending.order(:send_at).to_a +
                          scope.where.not(status: :scheduled).where(updated_at: 7.days.ago..).order(updated_at: :desc).limit(RECENT_LIMIT)
  end

  def create
    @scheduled_message = @conversation.scheduled_messages.create!(permitted_params.merge(created_by: Current.user))
    render :show
  end

  def update
    return render_not_pending unless @scheduled_message.status_scheduled?

    @scheduled_message.update!(permitted_params)
    render :show
  end

  def destroy
    return render_not_pending unless @scheduled_message.status_scheduled?

    @scheduled_message.cancel!('manual')
    render :show
  end

  # Sugestão de horário para os atalhos da tela: a hora em que a cliente
  # costuma responder, encaixada no horário comercial do salão.
  def best_time
    suggestion = Broadcasts::BestTimeService.new(Current.account).suggestion(@conversation.contact)
    render json: { hour: suggestion[:hour], at: suggestion[:at]&.iso8601 }
  end

  private

  def fetch_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def fetch_scheduled_message
    @scheduled_message = Current.account.scheduled_messages.find(params[:id])
    authorize @scheduled_message.conversation, :show?
  end

  def render_not_pending
    render json: { error: I18n.t('scheduled_messages.errors.not_pending') }, status: :unprocessable_entity
  end

  def permitted_params
    params.require(:scheduled_message).permit(:content, :send_at, :cancel_if_reply)
  end
end
