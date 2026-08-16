import { mount, flushPromises } from '@vue/test-utils';
import AthenasReportContainer from '../AthenasReportContainer.vue';

const accountReport = vi.fn();

vi.mock('dashboard/api/athenas', () => ({
  default: { accountReport: (...args) => accountReport(...args) },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values ? `${key}:${values.n}` : key),
  }),
}));

const report = (overrides = {}) => ({
  period_days: 30,
  timezone: 'America/Sao_Paulo',
  totals: { replies: 12, conversations: 8, cost_cents_brl: 900 },
  quality: {},
  credits: {},
  leads: {},
  revenue: {},
  bookings: { booked: 2 },
  flags: {},
  daily: [{ date: '2026-08-14', replies: 12, cost_cents_brl: 900 }],
  hourly: [{ hour: 9, replies: 12 }],
  agents: [{ id: 1, name: 'Marina', replies: 12 }],
  ...overrides,
});

// The children are covered by their own specs. What matters here is the
// fetching, the period and which state the card is in.
const stubs = {
  AthenasSummary: { props: ['report'], template: '<div class="summary" />' },
  AthenasTrendChart: {
    props: ['points', 'title', 'color'],
    template: '<div class="chart" />',
  },
  AthenasQualityPanel: { template: '<div class="quality" />' },
  AthenasAgentTable: {
    props: ['agents'],
    template: '<div class="agents">{{ agents.length }}</div>',
  },
  Spinner: true,
};

const mountCard = () => mount(AthenasReportContainer, { global: { stubs } });
const periodButton = (wrapper, days) =>
  wrapper
    .findAll('button')
    .find(button => button.text() === `ATHENAS_REPORT.DAYS:${days}`);

describe('AthenasReportContainer', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    accountReport.mockResolvedValue({ data: report() });
  });

  it('asks for the last thirty days when it mounts', async () => {
    mountCard();
    await flushPromises();

    expect(accountReport).toHaveBeenCalledWith({ days: 30 });
  });

  it('renders the panel once the numbers arrive', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('.summary').exists()).toBe(true);
    expect(wrapper.find('.agents').text()).toBe('1');
  });

  it('refetches when the period changes', async () => {
    const wrapper = mountCard();
    await flushPromises();

    await periodButton(wrapper, 7).trigger('click');
    await flushPromises();

    expect(accountReport).toHaveBeenLastCalledWith({ days: 7 });
  });

  // A skeleton here would collapse the card and jump the whole page every time
  // somebody changes the range.
  it('holds the previous render while the next period loads', async () => {
    const wrapper = mountCard();
    await flushPromises();
    let resolve;
    accountReport.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );

    await periodButton(wrapper, 90).trigger('click');
    await flushPromises();

    expect(wrapper.find('.summary').exists()).toBe(true);
    resolve({ data: report() });
  });

  // A wall of R$ 0,00 reads like a broken product, not an unused one.
  it('says there is nothing to measure instead of showing zeroes', async () => {
    accountReport.mockResolvedValue({ data: report({ agents: [] }) });
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('ATHENAS_REPORT.NO_AGENTS');
    expect(wrapper.find('.summary').exists()).toBe(false);
  });

  it('offers a retry instead of an empty card when the request fails', async () => {
    accountReport.mockRejectedValue(new Error('nope'));
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('ATHENAS_REPORT.FAILED');

    accountReport.mockResolvedValue({ data: report() });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'ATHENAS_REPORT.RETRY')
      .trigger('click');
    await flushPromises();

    expect(wrapper.find('.summary').exists()).toBe(true);
  });

  // Without it the quietest hour of the night reads as the busiest hour of the
  // afternoon and nobody can tell.
  it('says which clock the hours are drawn on', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('ATHENAS_REPORT.CHART.TIMEZONE');
  });
});
