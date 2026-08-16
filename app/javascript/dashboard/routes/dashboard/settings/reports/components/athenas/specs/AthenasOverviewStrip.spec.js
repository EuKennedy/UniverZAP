import { mount, flushPromises } from '@vue/test-utils';
import AthenasOverviewStrip from '../AthenasOverviewStrip.vue';

const accountReport = vi.fn();

vi.mock('dashboard/api/athenas', () => ({
  default: { accountReport: (...args) => accountReport(...args) },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
}));

const report = (overrides = {}) => ({
  totals: {
    replies: 1240,
    conversations: 310,
    revenue_brl: 4820.5,
    cost_cents_brl: 9900,
    roi: 4.87,
  },
  comparison: {
    replies: { previous: 1000, change: 24 },
    revenue_brl: { previous: 6000, change: -19.7 },
    cost_cents_brl: { previous: 9000, change: 10 },
  },
  bookings: { booked: 46 },
  agents: [{ id: 1, name: 'Marina' }],
  ...overrides,
});

const stubs = {
  Spinner: true,
  RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
};

const mountStrip = () => mount(AthenasOverviewStrip, { global: { stubs } });

describe('AthenasOverviewStrip', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    accountReport.mockResolvedValue({ data: report() });
  });

  // Janela fixa: o resto de Visão geral é ao vivo, e um segundo controle de
  // data numa página de relance convidaria a configurar em vez de olhar.
  it('asks for a fixed thirty day window', async () => {
    mountStrip();
    await flushPromises();

    expect(accountReport).toHaveBeenCalledWith({ days: 30 });
  });

  it('shows the headline numbers of the agents', async () => {
    const wrapper = mountStrip();
    await flushPromises();

    expect(wrapper.text()).toContain('1.240');
    expect(wrapper.text()).toContain('4,87x');
  });

  // Direção junto do número, senão 1.240 respostas não responde a única
  // pergunta que alguém faz olhando isso: é muito ou pouco?
  it('carries the direction against the window before', async () => {
    const wrapper = mountStrip();
    await flushPromises();

    expect(wrapper.text()).toContain('+24,0%');
    expect(wrapper.find('.text-n-ruby-11').text()).toContain('-19,7%');
  });

  it('opens the full report of the right account', async () => {
    const wrapper = mountStrip();
    await flushPromises();

    expect(wrapper.find('a').attributes('href')).toContain(
      '/accounts/7/reports/athenas'
    );
  });

  // Uma parede de R$ 0,00 na primeira tela da conta lê como produto quebrado,
  // não como produto não usado.
  it('renders nothing for an account with no agents', async () => {
    accountReport.mockResolvedValue({ data: report({ agents: [] }) });
    const wrapper = mountStrip();
    await flushPromises();

    expect(wrapper.text()).toBe('');
  });

  // Esta é uma seção secundária na página de abertura: se ela falhar, some, e
  // o resto de Visão geral segue respondendo.
  it('disappears instead of breaking the page when the request fails', async () => {
    accountReport.mockRejectedValue(new Error('nope'));
    const wrapper = mountStrip();
    await flushPromises();

    expect(wrapper.text()).toBe('');
  });
});
