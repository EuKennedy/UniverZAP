require 'rails_helper'

RSpec.describe Contacts::OriginService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }

  def conversation(**attrs)
    create(:conversation, account: account, inbox: inbox, contact: contact, **attrs)
  end

  it 'stamps organico on a contact with no ad conversation and creates the shared origem_lead definition' do
    conversation

    expect(described_class.new(contact).perform).to eq('organico')

    expect(contact.reload.custom_attributes['origem_lead']).to eq('organico')
    expect(account.custom_attribute_definitions.find_by(attribute_key: 'origem_lead', attribute_model: 'contact_attribute'))
      .to have_attributes(attribute_display_name: 'Lead origin', attribute_display_type: 'text')
  end

  it 'stamps anuncio_facebook when a conversation of the contact carries anuncio_id' do
    conversation(custom_attributes: { 'origem_lead' => 'anuncio_facebook', 'anuncio_id' => '42' })

    expect(described_class.new(contact).perform).to eq('anuncio_facebook')
    expect(contact.reload.custom_attributes['origem_lead']).to eq('anuncio_facebook')
  end

  it 'stamps anuncio_facebook when a conversation of the contact carries the lead-anuncio label' do
    create(:label, account: account, title: 'lead-anuncio')
    conversation.add_labels(['lead-anuncio'])

    expect(described_class.new(contact).perform).to eq('anuncio_facebook')
  end

  it 'never overwrites an origin already set' do
    contact.update!(custom_attributes: { 'origem_lead' => 'organico' })
    conversation(custom_attributes: { 'anuncio_id' => '42' })

    expect(described_class.new(contact).perform).to be_nil
    expect(contact.reload.custom_attributes['origem_lead']).to eq('organico')
  end

  it 'does nothing without a contact' do
    expect(described_class.new(nil).perform).to be_nil
  end
end
