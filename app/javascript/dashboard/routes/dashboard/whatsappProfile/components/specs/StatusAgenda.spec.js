import { mount, flushPromises } from '@vue/test-utils';
import StatusAgenda from '../StatusAgenda.vue';

const list = vi.fn();

vi.mock('dashboard/api/whatsappStatus', () => ({
  default: { list: (...a) => list(...a) },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const at = (days, hour) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
};

describe('StatusAgenda.vue', () => {
  it('lays the scheduled statuses on the next seven days', async () => {
    list.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            kind: 'text',
            body: 'Hoje',
            font: 0,
            recurrence: 'none',
            scheduled_at: at(0, 23),
          },
          {
            id: 2,
            kind: 'text',
            body: 'Daqui a 2',
            font: 0,
            recurrence: 'weekly',
            scheduled_at: at(2, 9),
          },
        ],
      },
    });

    const wrapper = mount(StatusAgenda, {
      global: { stubs: { StatusPreview: true, Spinner: true } },
    });
    await flushPromises();

    expect(list).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'scheduled', per: 50 })
    );
    const days = wrapper.findAll('[data-testid="agenda-day"]');
    expect(days).toHaveLength(7);
    expect(days[0].text()).toContain('Hoje');
    expect(days[2].text()).toContain('Daqui a 2');

    await days[2].find('[data-testid="agenda-item"]').trigger('click');
    expect(wrapper.emitted('edit')[0][0].id).toBe(2);
  });
});
