import { flushPromises, mount } from '@vue/test-utils';
import CatalogCard from '../CatalogCard.vue';
import { matches, scheduleSummary } from '../catalogFormat';

const getCatalog = vi.fn();

vi.mock('dashboard/api/integrations/belezaki', () => ({
  default: { getCatalog: (...args) => getCatalog(...args) },
}));

const weekdays = [1, 2, 3, 4, 5].map(weekday => ({
  weekday,
  start: '09:00',
  end: '18:00',
}));

const catalog = {
  status: 'ok',
  services: [
    {
      id: 's1',
      name: 'Coloração',
      duration_min: 120,
      price_cents: 22000,
      list_price_cents: 25000,
      is_promo: true,
      is_addon: false,
      professionals: [{ id: 'p2', name: 'Bianca' }],
    },
    {
      id: 's2',
      name: 'Corte feminino',
      duration_min: 60,
      price_cents: 12000,
      list_price_cents: 12000,
      is_promo: false,
      is_addon: false,
      professionals: [{ id: 'p1', name: 'Ana' }],
    },
  ],
  professionals: [
    {
      id: 'p1',
      name: 'Ana',
      role: 'Cabeleireira',
      performs_all: false,
      services: [{ id: 's2', name: 'Corte feminino' }],
      schedule: [...weekdays, { weekday: 6, start: '09:00', end: '14:00' }],
      has_schedule: true,
    },
    {
      id: 'p2',
      name: 'Bianca',
      role: 'Colorista',
      performs_all: false,
      services: [{ id: 's1', name: 'Coloração' }],
      schedule: [],
      has_schedule: false,
    },
  ],
};

const mountCard = async () => {
  const wrapper = mount(CatalogCard);
  await flushPromises();
  return wrapper;
};

describe('CatalogCard.vue', () => {
  beforeEach(() => {
    getCatalog.mockReset();
  });

  it('lists services with price, duration and promo, and the team with hours', async () => {
    getCatalog.mockResolvedValue({ data: catalog });

    const wrapper = await mountCard();

    expect(wrapper.findAll('[data-testid="catalog-service"]')).toHaveLength(2);
    expect(
      wrapper.findAll('[data-testid="catalog-professional"]')
    ).toHaveLength(2);
    const text = wrapper.text();
    expect(text).toContain('120 min');
    expect(text).toContain('Promo');
    expect(text).toMatch(/R\$\s?220(?:\.|,)00/);
    expect(text).toContain('No working hours set');
  });

  it('filters both lists by an accent-insensitive search', async () => {
    getCatalog.mockResolvedValue({ data: catalog });

    const wrapper = await mountCard();
    await wrapper.find('[data-testid="catalog-search"]').setValue('coloracao');

    expect(wrapper.findAll('[data-testid="catalog-service"]')).toHaveLength(1);
    expect(
      wrapper.findAll('[data-testid="catalog-professional"]')
    ).toHaveLength(1);
    expect(wrapper.text()).toContain('Bianca');
    expect(wrapper.text()).not.toContain('Corte feminino');
  });

  it('tells an unlinked account where to go', async () => {
    getCatalog.mockResolvedValue({ data: { status: 'not_linked' } });

    const wrapper = await mountCard();

    expect(wrapper.text()).toContain('Connect the belezaki salon in Apps');
  });
});

describe('catalogFormat', () => {
  it('folds a week into runs of equal hours', () => {
    const summary = scheduleSummary(
      [...weekdays, { weekday: 6, start: '09:00', end: '14:00' }],
      'en'
    );
    expect(summary).toBe('Mon–Fri 09:00–18:00, Sat 09:00–14:00');
  });

  it('matches ignoring case and accents', () => {
    expect(matches('COLORACAO', 'Coloração')).toBe(true);
    expect(matches('bia', 'Corte', 'Bianca')).toBe(true);
    expect(matches('x', 'Corte')).toBe(false);
  });
});
