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
  paid_at: '2026-10-20T14:00:00Z',
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
  total_count: orders.length,
  ...extra,
});

const mountCard = async (...responses) => {
  responses.forEach(data =>
    WoocommerceAPI.getOrders.mockResolvedValueOnce({ data })
  );
  const wrapper = mount(StoreOrdersCard, {
    props: { contactId: 7 },
    attachTo: document.body,
  });
  await flushPromises();
  return wrapper;
};

const toggles = wrapper =>
  wrapper.findAll('[data-testid="store-order-toggle"]');
const openNumbers = wrapper =>
  toggles(wrapper)
    .filter(button => button.attributes('aria-expanded') === 'true')
    .map(button => button.text().match(/#(\d+)/)[1]);

describe('StoreOrdersCard', () => {
  beforeEach(() => {
    WoocommerceAPI.getOrders.mockReset();
    Element.prototype.scrollIntoView = vi.fn();
  });

  it('shows who she is in the store, her spend and every order closed', async () => {
    const wrapper = await mountCard(
      page([order(2, { status: 'processing' }), order(1, { total: 50 })])
    );

    expect(WoocommerceAPI.getOrders).toHaveBeenCalledWith(7, 1);
    expect(wrapper.text()).toContain('Orders at lizzon.com.br');
    expect(wrapper.text()).toContain('Rosana Rita');
    expect(wrapper.find('[data-testid="store-recurring"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="store-stat-spent"]').text()).toMatch(
      /239[.,]90/
    );
    expect(wrapper.text()).toContain('2 orders');
    expect(toggles(wrapper)).toHaveLength(2);
    expect(toggles(wrapper)[0].text()).toContain('#1042');
    expect(toggles(wrapper)[0].text()).toContain('Paid');
    expect(toggles(wrapper)[0].text()).toContain('2 items');
    expect(openNumbers(wrapper)).toEqual([]);
  });

  it('opens the summary of the order clicked, one at a time', async () => {
    const wrapper = await mountCard(
      page([
        order(2, { tracking: { code: 'QB123456789BR', carrier: 'Correios' } }),
        order(1),
      ])
    );

    await toggles(wrapper)[0].trigger('click');
    expect(openNumbers(wrapper)).toEqual(['1042']);
    const summary = wrapper.findAll('[data-testid="store-order-summary"]')[0];
    expect(summary.text()).toContain('Booster Ativador 500ml');
    expect(summary.text()).toContain('× 2');
    expect(summary.text()).toContain('QB123456789BR');
    expect(summary.text()).toContain('paid on');
    expect(summary.text()).toContain('1 of 2');

    await toggles(wrapper)[1].trigger('click');
    expect(openNumbers(wrapper)).toEqual(['1041']);

    await toggles(wrapper)[1].trigger('click');
    expect(openNumbers(wrapper)).toEqual([]);
  });

  it('walks to the older order and loads the next page on the way', async () => {
    const wrapper = await mountCard(
      page([order(3), order(2)], { has_more: true, total_count: 3 }),
      page([order(1)], { has_more: false, total_count: 3 })
    );

    await toggles(wrapper)[1].trigger('click');
    await wrapper
      .findAll('[data-testid="store-order-older"]')[1]
      .trigger('click');
    await flushPromises();

    expect(WoocommerceAPI.getOrders).toHaveBeenLastCalledWith(7, 2);
    expect(openNumbers(wrapper)).toEqual(['1041']);
    expect(wrapper.text()).toContain('3 of 3');
    expect(wrapper.find('[data-testid="store-load-more"]').exists()).toBe(
      false
    );

    await wrapper
      .findAll('[data-testid="store-order-newer"]')[2]
      .trigger('click');
    await flushPromises();
    expect(openNumbers(wrapper)).toEqual(['1042']);
  });

  it('names a plugin status instead of showing its slug', async () => {
    const wrapper = await mountCard(
      page([
        order(2, { status: 'uvf-shipped' }),
        order(1, { status: 'abc-custom-step' }),
      ])
    );

    expect(toggles(wrapper)[0].text()).toContain('Shipped');
    expect(toggles(wrapper)[1].text()).toContain('Custom step');
  });

  it('shows only the first items of a long order until asked', async () => {
    const items = ['A', 'B', 'C', 'D', 'E'].map(name => ({
      name,
      quantity: 1,
      total: '1',
    }));
    const wrapper = await mountCard(page([order(1, { items })]));

    await toggles(wrapper)[0].trigger('click');
    const summary = () => wrapper.find('[data-testid="store-order-summary"]');
    expect(summary().text()).not.toContain('D');
    await summary().find('button').trigger('click');
    expect(summary().text()).toContain('E');
  });

  it('offers the payment link only while the order waits for payment', async () => {
    const pending = await mountCard(page([order(1, { status: 'pending' })]));
    expect(pending.text()).toContain('Payment link');

    const paid = await mountCard(page([order(1, { status: 'processing' })]));
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
