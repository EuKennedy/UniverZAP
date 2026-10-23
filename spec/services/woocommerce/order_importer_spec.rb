require 'rails_helper'

RSpec.describe Woocommerce::OrderImporter do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:connection) do
    StoreConnection.create!(account: account, store_url: 'https://loja.lizzon.com.br', consumer_key: 'ck_x', consumer_secret: 'cs_x')
  end
  let(:payload) { JSON.parse(Rails.root.join('spec/fixtures/files/woocommerce/order.json').read) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    %w[aguardando-pagamento pedido-confirmado enviado].each { |title| create(:label, account: account, title: title) }
  end

  def import(data = payload, **)
    described_class.new(connection, data, **).perform
  end

  it 'stores the order the way the sheet reads it', :aggregate_failures do
    order = import

    expect(order).to have_attributes(number: '1042', status: 'processing', total: 189.90, payment_method_title: 'Pix',
                                     customer_name: 'Rosana Rita', customer_email: 'Rosana@Example.com')
    expect(order.items.first).to include('name' => 'Booster Ativador 500ml', 'quantity' => 2,
                                         'image' => 'https://loja.lizzon.com.br/wp-content/uploads/booster.jpg')
    expect(order.tracking).to eq('code' => 'QB123456789BR', 'carrier' => 'Correios')
    expect(order.placed_at).to eq(Time.zone.parse('2026-10-20T13:00:00Z'))
  end

  it 'finds the WhatsApp contact by the checkout phone, ninth digit and country code included' do
    contact = create(:contact, account: account, phone_number: '+5531987654321')

    expect(import.contact).to eq(contact)
  end

  it 'falls back to the e-mail, case-insensitively' do
    contact = create(:contact, account: account, email: 'rosana@example.com')
    payload['billing']['phone'] = ''

    expect(import.contact).to eq(contact)
  end

  it 'creates the contact when the customer is new' do
    contact = import.contact

    expect(contact).to have_attributes(name: 'Rosana Rita', phone_number: '+5531987654321', email: 'rosana@example.com')
  end

  it 'updates the same row when the store sends the order again' do
    import
    payload['status'] = 'completed'
    payload['date_modified_gmt'] = '2026-10-21T10:00:00'

    expect { import }.not_to change(StoreOrder, :count)
    expect(StoreOrder.last.status).to eq('completed')
  end

  it 'ignores a payload older than the stored order' do
    import
    payload['status'] = 'pending'
    payload['date_modified_gmt'] = '2026-10-19T10:00:00'

    import
    expect(StoreOrder.last.status).to eq('processing')
  end

  describe 'on the open conversation' do
    let(:contact) { create(:contact, account: account, phone_number: '+5531987654321') }
    let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open) }

    it 'swaps the stage label for the new status and fills the order fields', :aggregate_failures do
      conversation.update!(label_list: %w[aguardando-pagamento vip])

      import

      conversation.reload
      expect(conversation.label_list).to contain_exactly('pedido-confirmado', 'vip')
      expect(conversation.custom_attributes).to include('numero_pedido' => '1042', 'valor_pedido' => 189.9, 'codigo_rastreio' => 'QB123456789BR')
    end

    it 'moves on when the order is shipped' do
      import
      payload['status'] = 'completed'
      payload['date_modified_gmt'] = '2026-10-21T10:00:00'

      import
      expect(conversation.reload.label_list).to eq(['enviado'])
    end

    it 'does not add a label the account does not have' do
      payload['status'] = 'refunded'

      import
      expect(conversation.reload.label_list).to be_empty
    end

    it 'leaves the conversation alone during the backfill' do
      import(silent: true)

      expect(conversation.reload.label_list).to be_empty
    end

    it 'leaves a resolved conversation alone' do
      conversation.update!(status: :resolved)

      import
      expect(conversation.reload.label_list).to be_empty
    end
  end
end
