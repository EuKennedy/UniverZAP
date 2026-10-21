# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::RecipientReport do
  let(:account) { create(:account) }
  let(:broadcast) { create(:broadcast, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def recipient(name, phone, **attrs)
    contact = create(:contact, account: account, name: name, phone_number: phone)
    create(:broadcast_recipient, broadcast: broadcast, contact: contact, **attrs)
  end

  def message_with(status)
    create(:message, :bot_message, conversation: conversation, account: account, inbox: conversation.inbox, status: status)
  end

  before do
    recipient('Ana Lima', '+5531900000001', status: :sent, sent_at: 2.hours.ago, message: message_with('read'))
    recipient('Bia Rocha', '+5531900000002', status: :sent, sent_at: 1.hour.ago, replied_at: 30.minutes.ago, message: message_with('delivered'))
    recipient('Carla Dias', '+5531900000003', status: :sent, sent_at: 1.hour.ago, message: message_with('failed'))
    recipient('Duda Melo', '+5531900000004', status: :failed, error: 'sessão caiu')
    recipient('Eva Souza', '+5531900000005', status: :skipped, skip_reason: 'opted_out')
  end

  def names(filter: 'all', query: nil)
    described_class.new(broadcast, filter: filter, query: query).scope.map { |r| r.contact.name }
  end

  it 'filtra pelo resultado com a mesma régua das contagens' do
    expect(names(filter: 'delivered')).to contain_exactly('Ana Lima', 'Bia Rocha')
    expect(names(filter: 'read')).to contain_exactly('Ana Lima')
    expect(names(filter: 'replied')).to contain_exactly('Bia Rocha')
    expect(names(filter: 'failed')).to contain_exactly('Carla Dias', 'Duda Melo')
    expect(names(filter: 'skipped')).to contain_exactly('Eva Souza')
    expect(names(filter: 'qualquer')).to contain_exactly('Ana Lima', 'Bia Rocha', 'Carla Dias', 'Duda Melo', 'Eva Souza')
  end

  it 'busca por nome ou pelos dígitos do telefone, junto do filtro' do
    expect(names(query: 'bia')).to contain_exactly('Bia Rocha')
    expect(names(query: '(31) 90000-0004')).to contain_exactly('Duda Melo')
    expect(names(filter: 'failed', query: 'carla')).to contain_exactly('Carla Dias')
  end

  it 'gera o CSV com resultado e motivo em português' do
    I18n.with_locale(:pt_BR) do
      rows = CSV.parse(described_class.new(broadcast).to_csv)

      expect(rows.first).to eq(['Nome', 'Telefone', 'Resultado', 'Motivo', 'Erro', 'Enviada em', 'Respondeu em'])
      by_name = rows.drop(1).index_by(&:first)
      expect(by_name['Bia Rocha'][2]).to eq('Respondeu')
      expect(by_name['Ana Lima'][2]).to eq('Lida')
      expect(by_name['Duda Melo'].values_at(2, 4)).to eq(['Falhou', 'sessão caiu'])
      expect(by_name['Eva Souza'].values_at(2, 3)).to eq(['Pulada', 'Pediu para não receber'])
    end
  end
end
