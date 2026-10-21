import { mount, flushPromises } from '@vue/test-utils';
import StatusStatsBar from '../StatusStatsBar.vue';

const stats = vi.fn();

vi.mock('dashboard/api/whatsappStatus', () => ({
  default: { stats: (...a) => stats(...a) },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('StatusStatsBar.vue', () => {
  it('shows the four counters and hands the data to the page', async () => {
    stats.mockResolvedValue({
      data: {
        published_7d: 12,
        scheduled: 3,
        drafts: 2,
        failed_7d: 1,
        success_rate_30d: 92,
        next_scheduled_at: '2099-01-01T12:00:00Z',
      },
    });

    const wrapper = mount(StatusStatsBar);
    await flushPromises();

    const values = wrapper
      .findAll('[data-testid="stat-value"]')
      .map(node => node.text());
    expect(values).toEqual(['12', '3', '1', '92%']);
    expect(wrapper.emitted('loaded')[0][0].scheduled).toBe(3);
  });

  // Sem nada terminado, "0%" diria que tudo falhou.
  it('shows a dash instead of a success rate when nothing finished yet', async () => {
    stats.mockResolvedValue({
      data: {
        published_7d: 0,
        scheduled: 0,
        failed_7d: 0,
        success_rate_30d: null,
      },
    });

    const wrapper = mount(StatusStatsBar);
    await flushPromises();

    expect(
      wrapper
        .find('[data-testid="stat-success"] [data-testid="stat-value"]')
        .text()
    ).toBe('–');
  });
});
