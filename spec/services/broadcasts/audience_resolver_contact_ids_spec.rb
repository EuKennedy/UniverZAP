require 'rails_helper'

RSpec.describe Broadcasts::AudienceResolver, '#contact_ids' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:list) { create(:contact_list, account: account, source: 'group', group_identifier: '1@g.us') }
  let(:warm) { create(:contact, account: account, phone_number: '+5531988881111') }
  let(:cold) { create(:contact, account: account, phone_number: '+5531988882222', custom_attributes: { 'consentimento_disparo' => false }) }
  let(:broadcast) { create(:broadcast, account: account, audience: { 'contact_list_ids' => [list.id] }) }

  before do
    [warm, cold].each { |contact| create(:contact_list_member, contact_list: list, contact: contact) }
    create(:contact_list_member, contact_list: list, contact: create(:contact, account: account, phone_number: '+5531988883333'), status: :left)
    create(:contact_list_member, contact_list: list, contact: nil, wa_id: '7@lid')
  end

  def resolver
    described_class.new(broadcast.reload)
  end

  it 'inclui os ativos com telefone e deixa de fora quem nunca falou com o salão' do
    expect(resolver.contact_ids).to eq([warm.id])
    expect(resolver.unconsented_contact_ids).to eq([cold.id])
  end

  it 'inclui quem nunca falou quando o disparo tem a confirmação gravada' do
    broadcast.update!(cold_contacts_confirmed_at: Time.current)

    expect(resolver.contact_ids).to contain_exactly(warm.id, cold.id)
  end

  it 'quem já mandou mensagem numa conversa direta conta como consentido' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: cold)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: cold)

    expect(resolver.contact_ids).to contain_exactly(warm.id, cold.id)
  end

  it 'a etiqueta do grupo também respeita o consentimento' do
    cold.add_labels(['grupo-vip'])
    create(:label, account: account, title: 'grupo-vip')
    broadcast.update!(audience: { 'contact_label_ids' => [account.labels.find_by(title: 'grupo-vip').id] })

    expect(resolver.contact_ids).to be_empty
  end

  it 'lista de outra conta não entra' do
    foreign = create(:contact_list)
    create(:contact_list_member, contact_list: foreign, contact: create(:contact, account: foreign.account, phone_number: '+5531900000000'))
    broadcast.update!(audience: { 'contact_list_ids' => [foreign.id] })

    expect(resolver.contact_ids).to be_empty
  end

  it 'mudar o público apaga a confirmação' do
    broadcast.update!(cold_contacts_confirmed_at: Time.current)
    broadcast.update!(audience: { 'contact_list_ids' => [list.id], 'contact_ids' => [warm.id] })

    expect(broadcast).not_to be_cold_contacts_confirmed
  end
end
