# Upserts one WooCommerce order (the REST/webhook JSON) into store_orders and,
# when the status moved, reflects it on the customer's open conversation:
#   - the e-commerce stage label for the new status replaces the one the
#     previous status had (see STATUS_LABELS), only if the account has it;
#   - the order number, value and tracking code fill the sheet's attributes.
# A payload older than what is stored is ignored, so a late webhook cannot
# undo a newer status. `silent` (the history import) skips the conversation:
# old orders must not relabel today's chats.
class Woocommerce::OrderImporter
  STATUS_LABELS = {
    'pending' => 'aguardando-pagamento',
    'on-hold' => 'aguardando-pagamento',
    'processing' => 'pedido-confirmado',
    'completed' => 'enviado',
    'failed' => 'pagamento-recusado',
    'refunded' => 'reembolso'
  }.freeze
  OPEN_STATUSES = %w[open pending snoozed].freeze
  TRACKING_KEYS = %w[_correios_tracking_code _tracking_number _aftership_tracking_number codigo_rastreio].freeze

  def initialize(connection, payload, silent: false)
    @connection = connection
    @account = connection.account
    @payload = payload
    @silent = silent
  end

  def perform
    order = @connection.store_orders.find_or_initialize_by(external_id: @payload['id'].to_s)
    return order if stale?(order)

    status_changed = order.status != @payload['status']
    order.assign_attributes(attributes)
    order.account = @account
    order.contact ||= store_account_contact || Woocommerce::CustomerMatcher.new(@account, @payload['billing'] || {}).perform
    order.save!
    reflect_on_conversation(order) if status_changed && !@silent
    order
  end

  private

  # A registered customer is one account in the store: her orders stay on one
  # contact even when she checked out with another phone or e-mail.
  def store_account_contact
    return if customer_external_id.nil?

    contact_id = @connection.store_orders.where(customer_external_id: customer_external_id).where.not(contact_id: nil).pick(:contact_id)
    contact_id && @account.contacts.find_by(id: contact_id)
  end

  # WooCommerce sends 0 for a guest checkout.
  def customer_external_id
    @payload['customer_id'].to_i.positive? ? @payload['customer_id'].to_s : nil
  end

  def stale?(order)
    modified = time(@payload['date_modified_gmt'])
    order.persisted? && order.store_updated_at && modified && order.store_updated_at >= modified
  end

  def attributes
    order_fields.merge(customer_fields).merge(
      items: items,
      tracking: tracking,
      placed_at: time(@payload['date_created_gmt']),
      paid_at: time(@payload['date_paid_gmt']),
      store_updated_at: time(@payload['date_modified_gmt'])
    )
  end

  def order_fields
    {
      number: @payload['number'].presence || @payload['id'].to_s,
      status: @payload['status'],
      currency: @payload['currency'].presence || 'BRL',
      total: @payload['total'].to_d,
      payment_method: @payload['payment_method'],
      payment_method_title: @payload['payment_method_title'],
      payment_url: @payload['payment_url']
    }
  end

  def customer_fields
    billing = @payload['billing'] || {}
    {
      customer_name: [billing['first_name'], billing['last_name']].compact_blank.join(' '),
      customer_phone: billing['phone'],
      customer_email: billing['email'],
      customer_external_id: customer_external_id
    }
  end

  def items
    Array(@payload['line_items']).map do |item|
      { name: item['name'], quantity: item['quantity'], total: item['total'], sku: item['sku'], image: item.dig('image', 'src') }.compact
    end
  end

  # Tracking lives in plugin meta: the Shipment Tracking list or a plain code.
  def tracking
    meta = Array(@payload['meta_data']).to_h { |entry| [entry['key'], entry['value']] }
    shipment = Array(meta['_wc_shipment_tracking_items']).first
    if shipment
      return { code: shipment['tracking_number'], carrier: shipment['tracking_provider'],
               url: shipment['custom_tracking_link'] }.compact_blank
    end

    code = meta.values_at(*TRACKING_KEYS).find(&:present?)
    code ? { code: code.to_s } : {}
  end

  def time(value)
    value.present? ? Time.zone.parse("#{value}Z") : nil
  end

  def reflect_on_conversation(order)
    conversation = open_conversation(order.contact)
    return if conversation.nil?

    conversation.update!(label_list: next_labels(conversation, order), custom_attributes: conversation.custom_attributes.merge(sheet_fields(order)))
  end

  def open_conversation(contact)
    return if contact.nil?

    contact.conversations.where(status: OPEN_STATUSES).order(last_activity_at: :desc).first
  end

  def next_labels(conversation, order)
    labels = conversation.label_list.to_a - STATUS_LABELS.values
    target = STATUS_LABELS[order.status]
    target && @account.labels.exists?(title: target) ? labels | [target] : labels
  end

  def sheet_fields(order)
    { 'numero_pedido' => order.number, 'valor_pedido' => order.total.to_f, 'codigo_rastreio' => order.tracking['code'] }.compact_blank
  end
end
