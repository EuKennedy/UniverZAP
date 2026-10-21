# Sequências de mensagens presas ao horário agendado. Só administrador cria,
# edita ou liga: ligar uma sequência é autorizar mensagem automática saindo
# pelo número do salão.
class Api::V1::Accounts::MessageSequencesController < Api::V1::Accounts::BaseController
  before_action :fetch_message_sequence, only: [:update, :destroy]
  before_action :authorize_action

  def index
    @message_sequences = Current.account.message_sequences.order(:id)
  end

  def create
    @message_sequence = Current.account.message_sequences.create!(permitted_params)
    render :show
  end

  def update
    @message_sequence.update!(permitted_params)
    # Desligar cancela o que ainda não saiu; ligar vale para os próximos agendamentos.
    @message_sequence.scheduled_messages.pending.find_each { |scheduled| scheduled.cancel!('sequence_disabled') } unless @message_sequence.enabled
    render :show
  end

  def destroy
    @message_sequence.scheduled_messages.pending.find_each { |scheduled| scheduled.cancel!('sequence_disabled') }
    @message_sequence.destroy!
    head :ok
  end

  private

  def fetch_message_sequence
    @message_sequence = Current.account.message_sequences.find(params[:id])
  end

  def authorize_action
    authorize(@message_sequence || MessageSequence)
  end

  def permitted_params
    params.require(:message_sequence).permit(:name, :enabled, :inbox_id, steps: [:offset_minutes, :text, :cancel_if_reply])
  end
end
