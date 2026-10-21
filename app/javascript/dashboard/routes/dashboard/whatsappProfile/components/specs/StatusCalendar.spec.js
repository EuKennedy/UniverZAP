import { mount, flushPromises } from '@vue/test-utils';
import StatusCalendar from '../StatusCalendar.vue';

const list = vi.fn();
const reschedule = vi.fn();

vi.mock('dashboard/api/whatsappStatus', () => ({
  default: {
    list: (...a) => list(...a),
    reschedule: (...a) => reschedule(...a),
  },
}));
vi.mock('dashboard/api/whatsappStatusCampaigns', () => ({
  default: { list: vi.fn().mockResolvedValue({ data: { payload: [] } }) },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Select: true,
};

const inDays = (days, hour = 10) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, 0, 0, 0);
  return date;
};

describe('StatusCalendar.vue', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows the month with each post on its day and the campaign colour', async () => {
    const day = inDays(1);
    list.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            kind: 'text',
            body: 'Agenda',
            status: 'scheduled',
            scheduled_at: day.toISOString(),
            campaign: { id: 3, name: 'Escova', color: '#B03A2E' },
          },
        ],
      },
    });

    const wrapper = mount(StatusCalendar, { global: { stubs } });
    await flushPromises();

    expect(list).toHaveBeenCalledWith(
      expect.objectContaining({
        per: 200,
        from: expect.any(String),
        until: expect.any(String),
      })
    );
    expect(wrapper.findAll('[data-testid="calendar-day"]')).toHaveLength(42);
    const post = wrapper.find('[data-testid="calendar-post"]');
    expect(post.text()).toContain('Escova');
    expect(post.find('.bg-\\[\\#B03A2E\\]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="calendar-legend"]').text()).toContain(
      'Escova'
    );
  });

  // Arrastar remarca mantendo o horário; só o que ainda vai sair se move.
  it('reschedules a dragged post to the target day keeping the time', async () => {
    const day = inDays(1, 9);
    list.mockResolvedValue({
      data: {
        payload: [
          {
            id: 4,
            kind: 'text',
            body: 'A',
            status: 'scheduled',
            scheduled_at: day.toISOString(),
          },
        ],
      },
    });
    reschedule.mockResolvedValue({});

    const wrapper = mount(StatusCalendar, { global: { stubs } });
    await flushPromises();
    const target = inDays(3, 0);
    const cells = wrapper.findAll('[data-testid="calendar-day"]');
    const targetCell = cells.find(
      cell =>
        cell.text().startsWith(String(target.getDate())) &&
        !cell.classes().includes('opacity-60')
    );

    await wrapper
      .find('[data-testid="calendar-post"]')
      .trigger('dragstart', { dataTransfer: { effectAllowed: '' } });
    await targetCell.trigger('drop');
    await flushPromises();

    const [id, iso] = reschedule.mock.calls[0];
    expect(id).toBe(4);
    const moved = new Date(iso);
    expect([moved.getDate(), moved.getHours()]).toEqual([target.getDate(), 9]);
  });

  it('asks the page to open the composer on a future day', async () => {
    list.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mount(StatusCalendar, { global: { stubs } });
    await flushPromises();

    await wrapper.find('[data-testid="calendar-add"]').trigger('click');

    expect(wrapper.emitted('create')[0][0]).toBeInstanceOf(Date);
  });
});
