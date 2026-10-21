import { flushPromises, mount } from '@vue/test-utils';
import Woocommerce from '../Woocommerce.vue';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';

const dispatch = vi.fn();

vi.mock('dashboard/api/integrations/woocommerce', () => ({
  default: {
    get: vi.fn(),
    connect: vi.fn(),
    sync: vi.fn(),
    disconnect: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

const mountPage = async state => {
  WoocommerceAPI.get.mockResolvedValue({ data: state });
  const wrapper = mount(Woocommerce, {
    global: {
      stubs: {
        // The global NextButton stub drops `label` and `disabled`.
        NextButton: {
          props: ['label', 'disabled'],
          template:
            '<button :disabled="disabled" v-bind="$attrs">{{ label }}</button>',
        },
        WootLoadingState: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('Woocommerce settings', () => {
  beforeEach(() => vi.clearAllMocks());

  it('walks the admin through the keys and connects the store', async () => {
    WoocommerceAPI.connect.mockResolvedValue({
      data: {
        connected: true,
        status: 'connected',
        store_url: 'https://loja.x',
        orders_count: 0,
      },
    });
    const wrapper = await mountPage({ connected: false });
    expect(wrapper.text()).toContain(
      'WooCommerce › Settings › Advanced › REST API'
    );

    await wrapper.find('#woo-url').setValue('https://loja.x');
    await wrapper.find('#woo-key').setValue('ck_1');
    await wrapper.find('#woo-secret').setValue('cs_1');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(WoocommerceAPI.connect).toHaveBeenCalledWith({
      store_url: 'https://loja.x',
      consumer_key: 'ck_1',
      consumer_secret: 'cs_1',
    });
    expect(wrapper.find('[data-testid="woo-status"]').text()).toContain(
      'Connected'
    );
    expect(dispatch).toHaveBeenCalledWith('integrations/get');
  });

  it('shows why the store refused the keys', async () => {
    WoocommerceAPI.connect.mockRejectedValue({
      response: {
        data: { error: 'WooCommerce respondeu 401: Chave inválida' },
      },
    });
    const wrapper = await mountPage({ connected: false });

    await wrapper.find('#woo-url').setValue('https://loja.x');
    await wrapper.find('#woo-key').setValue('ck_1');
    await wrapper.find('#woo-secret').setValue('cs_1');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[data-testid="woo-error"]').text()).toBe(
      'WooCommerce respondeu 401: Chave inválida'
    );
  });

  it('shows the counters and the error of a connected store', async () => {
    const wrapper = await mountPage({
      connected: true,
      status: 'failing',
      store_url: 'https://loja.x',
      orders_count: 120,
      linked_orders_count: 98,
      last_error: 'WooCommerce respondeu 401',
    });

    expect(wrapper.find('[data-testid="woo-status"]').text()).toContain(
      'Needs attention'
    );
    expect(wrapper.text()).toContain('120');
    expect(wrapper.text()).toContain('98');
    expect(wrapper.text()).toContain('WooCommerce respondeu 401');
  });
});
