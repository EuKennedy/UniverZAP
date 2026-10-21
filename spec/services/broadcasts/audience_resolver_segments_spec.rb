# frozen_string_literal: true

require 'rails_helper'

# Os filtros de segmento estreitam o público (E), ao contrário das etiquetas e
# listas, que somam (OU).
RSpec.describe Broadcasts::AudienceResolver do
  let(:account) { create(:account) }
  let!(:ad_lead) { create(:contact, account: account, phone_number: '+5531900000001', custom_attributes: { 'origem_lead' => 'anuncio_facebook' }) }
  let!(:returning) do
    create(:contact, account: account, phone_number: '+5531900000002', custom_attributes: { 'origem_lead' => 'organico', 'recorrente' => true })
  end
  let!(:birthday) { create(:contact, account: account, phone_number: '+5531900000003', custom_attributes: { 'data_nascimento' => '1990-10-21' }) }

  def ids(audience)
    described_class.new(create(:broadcast, account: account, audience: audience)).contact_ids
  end

  it 'filtra a base inteira por origem quando não há outro filtro' do
    expect(ids('origins' => ['anuncio_facebook'])).to contain_exactly(ad_lead.id)
  end

  it 'filtra recorrentes e não recorrentes' do
    expect(ids('recurring' => 'yes')).to contain_exactly(returning.id)
    expect(ids('recurring' => 'no')).to contain_exactly(ad_lead.id, birthday.id)
  end

  it 'estreita a lista escolhida em vez de somar' do
    expect(ids('contact_ids' => [ad_lead.id, returning.id], 'origins' => ['organico'])).to contain_exactly(returning.id)
  end

  it 'acha quem não responde há X dias (e já conversou alguma vez)' do
    quiet = create(:conversation, account: account, contact: returning)
    create(:message, conversation: quiet, account: account, inbox: quiet.inbox, message_type: :incoming, created_at: 40.days.ago)
    active = create(:conversation, account: account, contact: ad_lead)
    create(:message, conversation: active, account: account, inbox: active.inbox, message_type: :incoming, created_at: 2.days.ago)

    expect(ids('no_reply_days' => 30)).to contain_exactly(returning.id)
  end

  it 'acha as aniversariantes da semana' do
    travel_to(Time.zone.parse('2026-10-20 12:00')) do
      expect(ids('birthday' => 'week')).to contain_exactly(birthday.id)
      expect(ids('birthday' => 'today')).to be_empty
    end
  end

  it 'tira quem tem a etiqueta excluída' do
    label = create(:label, account: account, title: 'nao-perturbe')
    ad_lead.update!(label_list: ['nao-perturbe'])

    expect(ids('origins' => %w[anuncio_facebook organico], 'exclude_label_ids' => [label.id])).to contain_exactly(returning.id)
  end
end
