import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import CustomerCard from '../CustomerCard.vue';

const getCustomer = vi.fn();
const isAdmin = ref(true);

vi.mock('dashboard/api/integrations/belezaki', () => ({
  default: { getCustomer: (...args) => getCustomer(...args) },
}));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentAccountId: ref(7) }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin }),
}));

const appointment = (id, status, start) => ({
  id,
  status,
  service: 'Escova',
  professional: 'Ana',
  start,
  end: start,
});

const mountCard = async () => {
  const wrapper = mount(CustomerCard, { props: { contactId: 42 } });
  await flushPromises();
  return wrapper;
};

describe('CustomerCard.vue', () => {
  beforeEach(() => {
    getCustomer.mockReset();
    isAdmin.value = true;
  });

  it('asks the salon for the contact and shows the next appointment first', async () => {
    getCustomer.mockResolvedValue({
      data: {
        status: 'ok',
        salon: { name: 'Bella', timezone: 'America/Sao_Paulo' },
        client: { id: 'c1', name: 'Maria Souza', phone: '5531984956383' },
        next: appointment('a-next', 'confirmed', '2026-10-20T14:00:00-03:00'),
        upcoming: [
          appointment('a-next', 'confirmed', '2026-10-20T14:00:00-03:00'),
          appointment('a-later', 'cancelled', '2026-10-25T09:00:00-03:00'),
        ],
        history: [appointment('a-old', 'no_show', '2026-08-01T10:00:00-03:00')],
      },
    });

    const wrapper = await mountCard();

    expect(getCustomer).toHaveBeenCalledWith(42);
    const text = wrapper.text();
    expect(text).toContain('Maria Souza');
    expect(text).toContain('Bella');
    expect(text).toMatch(/14:00/);
    // the next appointment is not repeated under "also scheduled"
    expect(text.match(/Escova/g)).toHaveLength(3);
  });

  it('shows the salon figures, the recurring badge, prices and a pending deposit', async () => {
    getCustomer.mockResolvedValue({
      data: {
        status: 'ok',
        salon: { name: 'Bella', timezone: 'America/Sao_Paulo' },
        client: { id: 'c1', name: 'Maria Souza', phone: '5531984956383' },
        stats: {
          visits: 2,
          no_shows: 1,
          total_spent_cents: 20000,
          ticket_avg_cents: 10000,
          last_visit_at: '2026-10-09T14:00:00-03:00',
          recurrent: true,
          cashback_cents: 300,
        },
        next: {
          ...appointment('a-next', 'scheduled', '2026-10-20T14:00:00-03:00'),
          price_cents: 9000,
          needs_deposit: true,
        },
        upcoming: [],
        history: [],
      },
    });

    const wrapper = await mountCard();

    const text = wrapper.text();
    expect(wrapper.find('[data-testid="recurrent"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="belezaki-stats"]').text()).toContain(
      'No-shows'
    );
    expect(text).toContain('Scheduled');
    expect(text).toContain('Deposit pending');
    // money and the last visit are rendered, not left as cents or ISO
    expect(text).toMatch(/R\$\s?200(?:\.|,)00/);
    expect(text).toMatch(/R\$\s?90(?:\.|,)00/);
    expect(text).toContain('2026');
  });

  it('says there is nothing booked when every upcoming row is cancelled', async () => {
    getCustomer.mockResolvedValue({
      data: {
        status: 'ok',
        salon: { name: 'Bella' },
        client: { name: 'Maria' },
        next: null,
        upcoming: [
          appointment('a-later', 'cancelled', '2026-10-25T09:00:00-03:00'),
        ],
        history: [],
      },
    });

    const wrapper = await mountCard();

    expect(wrapper.text()).toContain('No upcoming appointment');
    expect(wrapper.text()).toContain('No visits in the last 12 months');
  });

  it('sends an admin to Apps when the salon is not connected', async () => {
    getCustomer.mockResolvedValue({ data: { status: 'not_linked' } });

    const wrapper = await mountCard();

    expect(wrapper.text()).toContain('Connect the belezaki salon in Apps');
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('hides the Apps button from agents', async () => {
    isAdmin.value = false;
    getCustomer.mockResolvedValue({ data: { status: 'not_linked' } });

    const wrapper = await mountCard();

    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('offers a retry when belezaki does not answer', async () => {
    getCustomer.mockResolvedValue({
      data: { status: 'unavailable', error: 'http_503' },
    });

    const wrapper = await mountCard();

    expect(wrapper.text()).toContain('http_503');
    getCustomer.mockResolvedValue({
      data: { status: 'unknown_client', salon: { name: 'Bella' } },
    });
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Not a customer at Bella yet');
    expect(getCustomer).toHaveBeenCalledTimes(2);
  });
});
