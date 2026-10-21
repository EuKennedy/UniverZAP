require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) do
    Chatflow.create!(account: account, name: 'Lembrete', inbox: inbox, status: :active, trigger_type: :keyword,
                     trigger_config: { 'keywords' => ['oi'] })
  end
  let(:on_reply) { 'stop' }
  let!(:wait) { flow_node(chatflow, :wait, 'mode' => 'duration', 'amount' => 2, 'unit' => 'hours', 'on_reply' => on_reply) }
  let!(:reminder) { flow_node(chatflow, :send_message, 'text' => 'Passando para lembrar!') }
  let!(:replied) { flow_node(chatflow, :send_message, 'text' => 'Que bom que respondeu!') }

  before do
    chatflow.update!(start_node: wait)
    flow_edge(wait, reminder)
    flow_edge(wait, replied, ChatflowNode::REPLIED)
  end

  def scanner_tick
    ScheduledMessages::DueScannerJob.perform_now
    perform_enqueued_jobs(only: Chatflow::ResumeJob)
  end

  it 'programa o relógio e o scanner das agendadas solta a espera' do
    freeze_time do
      customer_says(conversation, 'oi')
      execution = ChatflowExecution.last
      expect(execution.resume_at).to eq(2.hours.from_now)

      travel 1.hour
      scanner_tick
      expect(bot_said(conversation)).to be_empty

      travel 61.minutes
      scanner_tick
      expect(bot_said(conversation)).to eq(['Passando para lembrar!'])
      expect(execution.reload).to be_status_completed
    end
  end

  it 'até uma data: espera até o horário escolhido' do
    wait.update!(config: { 'mode' => 'until', 'until' => '2026-12-24T18:00:00-03:00' })
    travel_to(Time.zone.parse('2026-12-20T10:00:00-03:00')) do
      customer_says(conversation, 'oi')
      expect(ChatflowExecution.last.resume_at).to eq(Time.zone.parse('2026-12-24T18:00:00-03:00'))
    end
  end

  it 'na janela de envio: empurra para a próxima abertura' do
    wait.update!(config: wait.config.merge('respect_window' => true))
    travel_to(ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 10, 21, 18, 30)) do
      customer_says(conversation, 'oi')
      expect(ChatflowExecution.last.resume_at).to eq(ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 10, 22, 9))
    end
  end

  context 'when the customer writes during the wait (cliente escreve)' do
    it 'por padrão encerra o fluxo e o relógio não manda nada' do
      customer_says(conversation, 'oi')
      customer_says(conversation, 'já resolvi, obrigada')

      travel 3.hours do
        scanner_tick
      end
      expect(bot_said(conversation)).to be_empty
      expect(ChatflowExecution.last).to be_status_completed
    end

    context 'with on_reply keep (continuar esperando)' do
      let(:on_reply) { 'keep' }

      it 'ignora a mensagem e manda no horário' do
        customer_says(conversation, 'oi')
        customer_says(conversation, 'ok')
        travel 3.hours do
          scanner_tick
        end
        expect(bot_said(conversation)).to eq(['Passando para lembrar!'])
      end
    end

    context 'with on_reply branch (saída Respondeu)' do
      let(:on_reply) { 'branch' }

      it 'segue pela porta Respondeu' do
        customer_says(conversation, 'oi')
        customer_says(conversation, 'tô aqui')
        expect(bot_said(conversation)).to eq(['Que bom que respondeu!'])
      end
    end
  end

  it 'o timer que perdeu a corrida para a resposta não faz nada' do
    customer_says(conversation, 'oi')
    execution = ChatflowExecution.last
    execution.update!(resume_at: 1.minute.ago)
    customer_says(conversation, 'respondi')

    described_class.resume(execution.reload)
    expect(bot_said(conversation)).to be_empty
  end
end
