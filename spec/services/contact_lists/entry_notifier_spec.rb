require 'rails_helper'

RSpec.describe ContactLists::EntryNotifier do
  let(:account) { create(:account) }
  let(:list) { create(:contact_list, account: account) }
  let(:warm) { create(:contact, account: account, phone_number: '+5531988881111') }
  let(:cold) { create(:contact, account: account, phone_number: '+5531988882222', custom_attributes: { 'consentimento_disparo' => false }) }
  let(:dispatcher) { Chatflow::TriggerDispatcher }

  # O Chatflow vive em outra branch; aqui basta a mesma assinatura.
  before do
    stub_const('Chatflow::TriggerDispatcher', Class.new { def self.list_entered(_list, _contact); end })
    allow(Chatflow::TriggerDispatcher).to receive(:list_entered)
  end

  it 'avisa o Chatflow de quem entrou, menos quem nunca falou com o salão' do
    described_class.call(list, [warm.id, cold.id])

    expect(dispatcher).to have_received(:list_entered).with(list, warm).once
    expect(dispatcher).not_to have_received(:list_entered).with(list, cold)
  end

  it 'não faz nada sem o Chatflow instalado' do
    hide_const('Chatflow::TriggerDispatcher')

    expect { described_class.call(list, [warm.id]) }.not_to raise_error
  end

  describe 'pelo MemberService' do
    it 'com notify avisa só quem entrou de fato (novo ou que tinha saído)' do
      returning = create(:contact, account: account, phone_number: '+5531988883333')
      create(:contact_list_member, contact_list: list, contact: returning, status: :left)
      create(:contact_list_member, contact_list: list, contact: create(:contact, account: account, phone_number: '+5531988884444'))
      service = ContactLists::MemberService.new(list)

      service.add([warm.id, returning.id, list.members.status_active.first.contact_id], notify: true)

      expect(service.added_ids).to contain_exactly(warm.id, returning.id)
      expect(dispatcher).to have_received(:list_entered).twice
    end

    it 'sem notify (o bloco do Chatflow) não dispara nada' do
      ContactLists::MemberService.new(list).add([warm.id])

      expect(dispatcher).not_to have_received(:list_entered)
    end
  end
end
