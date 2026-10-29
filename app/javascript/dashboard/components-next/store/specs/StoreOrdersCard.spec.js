import { flushPromises, mount } from '@vue/test-utils';
import StoreOrdersCard from '../StoreOrdersCard.vue';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';

vi.mock('dashboard/api/integrations/woocommerce', () => ({
  default: { getOrders: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const order = (id, extra = {}) => ({
  id,
  number: String(1040 + id),
  status: 'completed',
  currency: 'BRL',
  total: 189.9,
  payment_method_title: 'Pix',
  payment_url: 'https://loja.x/pay',
  items: [{ name: 'Booster Ativador 500ml', quantity: 2, total: '159.80' }],
  tracking: {},
  placed_at: '2026-10-20T13:00:00Z',
  admin_url: `https://loja.x/wp-admin/post.php?post=${id}&action=edit`,
  ...extra,
});

const page = (orders, extra = {}) => ({
  connected: true,
  store_name: 'lizzon.com.br',
  customer: { customer_name: 'Rosana Rita', customer_email: 'rosana@x.com' },
  metrics: {
    orders_count: 2,
    total_spent: 239.9,
    average_ticket: 119.95,
    last_order_at: '2026-10-20T13:00:00Z',
  },
  orders,
  has_more: false,
  ...extra,
});

const mountCard = async (...responses) => {
  responses.forEach(data =>
    WoocommerceAPI.getOrders.mockResolvedValueOnce({ data })
  );
  const wrapper = mount(StoreOrdersCard, { props: { contactId: 7 } });
  await flushPromises();
  return wrapper;
};

describe('StoreOrdersCard', () => {
  beforeEach(() => WoocommerceAPI.getOrders.mockReset());

  it('shows who she is in the store, her spend and the order on its way', async () => {
    const wrapper = await mountCard(
      page([
        order(2, {
          status: 'processing',
          tracking: { code: 'QB123456789BR', carrier: 'Correios' },
        }),
        order(1, { total: 50 }),
      ])
    );

    expect(WoocommerceAPI.getOrders).toHaveBeenCalledWith(7, 1);
    expect(wrapper.text()).toContain('Orders at lizzon.com.br');
    expect(wrapper.text()).toContain('Rosana Rita · customer of lizzon.com.br');
    expect(wrapper.find('[data-testid="store-recurring"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="store-stat-spent"]').text()).toMatch(
      /239[.,]90/
    );
    const current = wrapper.find('[data-testid="store-current-order"]');
    expect(current.text()).toContain('Order #1042');
    expect(current.text()).toContain('Paid');
    expect(current.text()).toContain('2× Booster Ativador 500ml');
    expect(current.text()).toContain('QB123456789BR');
    expect(wrapper.text()).toContain('Order #1041');
    expect(wrapper.text()).toContain('Shipped');
  });

  it('keeps a delivered order in the history, with nothing in progress', async () => {
    const wrapper = await mountCard(page([order(1)]));

    expect(wrapper.find('[data-testid="store-current-order"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('No order in progress');
    expect(wrapper.findAll('[data-testid="store-order-row"]')).toHaveLength(1);
  });

  it('offers the payment link only while the order waits for payment', async () => {
    const pending = await mountCard(page([order(1, { status: 'pending' })]));
    expect(pending.text()).toContain('Payment link');

    const paid = await mountCard(page([order(1, { status: 'processing' })]));
    expect(paid.text()).not.toContain('Payment link');
  });

  it('loads older orders on demand', async () => {
    const wrapper = await mountCard(
      page([order(3), order(2)], { has_more: true }),
      page([order(1)], { has_more: false })
    );

    await wrapper.find('[data-testid="store-load-more"]').trigger('click');
    await flushPromises();

    expect(WoocommerceAPI.getOrders).toHaveBeenLastCalledWith(7, 2);
    expect(wrapper.findAll('[data-testid="store-order-row"]')).toHaveLength(3);
    expect(wrapper.find('[data-testid="store-load-more"]').exists()).toBe(
      false
    );
  });

  it('stays hidden while no store is connected', async () => {
    const wrapper = await mountCard({
      connected: false,
      metrics: {},
      orders: [],
    });

    expect(wrapper.find('[data-testid="store-orders"]').exists()).toBe(false);
  });
});
