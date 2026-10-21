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
  status: 'processing',
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

const mountCard = async data => {
  WoocommerceAPI.getOrders.mockResolvedValue({ data });
  const wrapper = mount(StoreOrdersCard, { props: { contactId: 7 } });
  await flushPromises();
  return wrapper;
};

describe('StoreOrdersCard', () => {
  it('shows the spend and the last order with items and tracking', async () => {
    const wrapper = await mountCard({
      connected: true,
      metrics: {
        orders_count: 2,
        total_spent: 239.9,
        average_ticket: 119.95,
        last_order_at: '2026-10-20T13:00:00Z',
      },
      orders: [
        order(2, {
          status: 'completed',
          tracking: { code: 'QB123456789BR', carrier: 'Correios' },
        }),
        order(1, { total: 50 }),
      ],
    });

    expect(WoocommerceAPI.getOrders).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="store-stat-orders"]').text()).toContain(
      '2'
    );
    expect(wrapper.find('[data-testid="store-stat-spent"]').text()).toMatch(
      /239[.,]90/
    );
    const latest = wrapper.find('[data-testid="store-latest-order"]');
    expect(latest.text()).toContain('Order #1042');
    expect(latest.text()).toContain('Shipped');
    expect(latest.text()).toContain('2× Booster Ativador 500ml');
    expect(latest.text()).toContain('QB123456789BR');
    expect(wrapper.text()).toContain('Order #1041');
  });

  it('offers the payment link only while the order waits for payment', async () => {
    const pending = await mountCard({
      connected: true,
      metrics: {},
      orders: [order(1, { status: 'pending' })],
    });
    expect(pending.text()).toContain('Payment link');

    const paid = await mountCard({
      connected: true,
      metrics: {},
      orders: [order(1)],
    });
    expect(paid.text()).not.toContain('Payment link');
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
