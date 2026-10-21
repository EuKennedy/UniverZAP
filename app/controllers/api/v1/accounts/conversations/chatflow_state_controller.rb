# O robô nesta conversa: qual fluxo está rodando, em que etapa, se está
# pausado — e os botões "Pausar robô" / "Retomar robô" do atendente.
class Api::V1::Accounts::Conversations::ChatflowStateController < Api::V1::Accounts::Conversations::BaseController
  def show
    render json: bot_control.state
  end

  def pause
    bot_control.pause!(by: Current.user)
    render json: bot_control.state
  end

  def resume
    bot_control.resume!
    render json: Chatflow::BotControl.new(@conversation.reload).state
  end

  private

  def bot_control
    @bot_control ||= Chatflow::BotControl.new(@conversation)
  end
end
