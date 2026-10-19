require 'rails_helper'

RSpec.describe Kanban::AutomationService do
  describe '.handle_conversation_resolved' do
    let(:account) { create(:account) }
    let(:funnel) { create(:funnel, account: account) }
    let!(:triage) { create(:funnel_stage, funnel: funnel, name: 'Triagem', position: 1) }
    let!(:won) { create(:funnel_stage, funnel: funnel, name: 'Concluído', status_type: :won, position: 2) }
    let!(:cancelled) { create(:funnel_stage, funnel: funnel, name: 'Cancelado', status_type: :lost, position: 3) }
    let(:conversation) { create(:conversation, account: account, status: :open) }
    let!(:task) { create(:kanban_task, account: account, funnel: funnel, funnel_stage: triage) }

    before do
      create(:label, account: account, title: 'cancelado', closes_conversation: true)
      create(:label, account: account, title: 'atendimento-encerrado', closes_conversation: true)
      task.conversations << conversation
    end

    it 'moves the card to the column named after the closing status' do
      conversation.update!(label_list: ['cancelado'], status: :resolved)

      described_class.handle_conversation_resolved(conversation.reload)

      expect(task.reload.funnel_stage).to eq(cancelled)
    end

    it 'is idempotent when the card is already in that column' do
      conversation.update!(label_list: ['cancelado'], status: :resolved)
      task.update!(funnel_stage: cancelled)

      expect { described_class.handle_conversation_resolved(conversation.reload) }
        .not_to(change { task.reload.updated_at })
    end

    it 'leaves the card alone when no column matches and the funnel does not win on resolve' do
      conversation.update!(label_list: ['atendimento-encerrado'], status: :resolved)

      described_class.handle_conversation_resolved(conversation.reload)

      expect(task.reload.funnel_stage).to eq(triage)
    end

    it 'falls back to the won column when the funnel wins on resolve' do
      funnel.update!(automation_settings: { 'auto_win_task_on_conversation_resolve' => true })
      conversation.update!(label_list: ['atendimento-encerrado'], status: :resolved)

      described_class.handle_conversation_resolved(conversation.reload)

      expect(task.reload.funnel_stage).to eq(won)
    end

    it 'prefers the named column over the won fallback' do
      funnel.update!(automation_settings: { 'auto_win_task_on_conversation_resolve' => true })
      conversation.update!(label_list: ['cancelado'], status: :resolved)

      described_class.handle_conversation_resolved(conversation.reload)

      expect(task.reload.funnel_stage).to eq(cancelled)
    end
  end

  describe '.handle_stage_label_applied' do
    let(:account) { create(:account) }
    let(:funnel) { create(:funnel, account: account) }
    let!(:triage) { create(:funnel_stage, funnel: funnel, name: 'Triagem', position: 1) }
    let!(:scheduled) { create(:funnel_stage, funnel: funnel, name: 'Agendado', position: 2) }
    let(:conversation) { create(:conversation, account: account, status: :open) }
    let!(:task) { create(:kanban_task, account: account, funnel: funnel, funnel_stage: triage) }

    before { task.conversations << conversation }

    it 'moves the card to the column named after the stage' do
      described_class.handle_stage_label_applied(conversation, 'agendado')

      expect(task.reload.funnel_stage).to eq(scheduled)
    end

    it 'leaves the card alone when no column has that name' do
      described_class.handle_stage_label_applied(conversation, 'confirmado')

      expect(task.reload.funnel_stage).to eq(triage)
    end

    it 'is idempotent when the card is already there' do
      task.update!(funnel_stage: scheduled)

      expect { described_class.handle_stage_label_applied(conversation, 'agendado') }
        .not_to(change { task.reload.updated_at })
    end
  end
end
