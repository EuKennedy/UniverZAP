require 'rails_helper'

# O modelo de listas vive em outra branch: aqui ele é simulado com o contrato
# combinado (ContactList + ContactLists::MemberService#add/#remove).
RSpec.describe Chatflow::ListBridge do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:list) { Struct.new(:id, :name, :account_id).new(9, 'VIP', account.id) }
  # rubocop:disable RSpec/VerifiedDoubles -- as classes de listas ainda não existem nesta branch
  let(:service) { double(add: 1, remove: 1) }
  let(:service_class) { double(new: service) }
  let(:list_class) { double(find_by: list) }
  # rubocop:enable RSpec/VerifiedDoubles

  before do
    stub_const('ContactList', list_class)
    stub_const('ContactLists::MemberService', service_class)
    allow(Chatflow::TriggerDispatcher).to receive(:list_entered)
  end

  it 'fica disponível quando o modelo existe' do
    expect(described_class.available?).to be(true)
  end

  it 'adiciona pelo MemberService e dispara "entrou na lista"' do
    expect(described_class.apply(account, contact, 9, 'add')).to be(true)

    expect(service).to have_received(:add).with([contact.id])
    expect(Chatflow::TriggerDispatcher).to have_received(:list_entered).with(list, contact)
  end

  it 'quem já estava na lista não dispara de novo' do
    allow(service).to receive(:add).and_return(0)
    described_class.apply(account, contact, 9, 'add')

    expect(Chatflow::TriggerDispatcher).not_to have_received(:list_entered)
  end

  it 'remove pelo MemberService' do
    described_class.apply(account, contact, 9, 'remove')

    expect(service).to have_received(:remove).with([contact.id])
  end

  it 'lista de outra conta não é encontrada' do
    allow(list_class).to receive(:find_by).and_return(nil)

    expect(described_class.apply(account, contact, 9, 'add')).to be(false)
  end
end
