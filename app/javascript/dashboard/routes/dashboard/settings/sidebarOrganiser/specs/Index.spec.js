import { mount, flushPromises } from '@vue/test-utils';
import Index from '../Index.vue';

const update = vi.fn();
const alerts = vi.fn();
const setLayout = vi.fn();

const menu = [
  { name: 'Inbox', label: 'Caixa de entrada', icon: 'i-lucide-inbox' },
  { name: 'Report', label: 'Relatórios', icon: 'i-lucide-chart' },
  {
    name: 'Conversation',
    label: 'Conversas',
    children: [{ name: 'All', label: 'Todas' }],
  },
];

let saved = {};

vi.mock('dashboard/api/sidebarLayout', () => ({
  default: { update: (...args) => update(...args) },
}));
vi.mock('dashboard/composables', () => ({ useAlert: (...a) => alerts(...a) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useSidebarLayout', () => ({
  useSidebarLayout: () => ({
    layout: { value: saved },
    menu: { value: menu },
    setLayout: (...a) => setLayout(...a),
  }),
}));

// Dragging itself belongs to vuedraggable. What matters here is that the lists
// it moves things between are wired to the right state.
const stubs = {
  Draggable: {
    props: ['modelValue'],
    template:
      '<ul><li v-for="e in modelValue" :key="e.name"><slot name="item" :element="e" /></li></ul>',
  },
  Button: {
    props: ['label', 'icon'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label || icon }}</button>',
  },
  Icon: true,
};

const mountScreen = () => mount(Index, { global: { stubs } });
const clickByLabel = (wrapper, label) =>
  wrapper
    .findAll('button')
    .find(b => b.text() === label)
    .trigger('click');
const placeholders = wrapper =>
  wrapper.findAll('input').map(i => i.attributes('placeholder'));

describe('SidebarOrganiser', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    saved = {};
    update.mockResolvedValue({ data: { layout: { version: 1 } } });
  });

  // The name of each item has to be readable, which is exactly what the first
  // attempt lost: a select with no width squeezed it out of the row.
  it('shows every leaf by its own name, loose, when nothing was saved', () => {
    const shown = placeholders(mountScreen());

    expect(shown).toContain('Caixa de entrada');
    expect(shown).toContain('Relatórios');
  });

  // Nesting one inside a custom group would be a third level the sidebar does
  // not render, so it is never offered as draggable.
  it('leaves a native group out of the lists', () => {
    expect(placeholders(mountScreen())).not.toContain('Conversas');
  });

  it('rebuilds the lists from a layout that was already saved', () => {
    saved = {
      version: 1,
      groups: [{ id: 'g_1', label: 'Gestão', order: 0 }],
      items: { Report: { group: 'g_1', order: 0, label: 'Números' } },
    };

    const wrapper = mountScreen();

    // v-model writes the DOM property, so the attribute selector would miss it.
    const values = wrapper.findAll('input').map(i => i.element.value);
    expect(values).toContain('Gestão');
    expect(values).toContain('Números');
  });

  it('creates a group ready to receive items', async () => {
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.ADD_GROUP');

    expect(wrapper.text()).toContain('SIDEBAR_ORGANISER.DROP_HERE');
  });

  // Deleting a group must never take its items down with it.
  it('sends the items home when a group is deleted', async () => {
    saved = {
      version: 1,
      groups: [{ id: 'g_1', label: 'Gestão', order: 0 }],
      items: { Report: { group: 'g_1', order: 0 } },
    };
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'i-lucide-trash-2');
    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.SAVE');
    await flushPromises();

    expect(update.mock.calls[0][0].items.Report.group).toBeUndefined();
  });

  it('saves the whole layout and updates the live sidebar', async () => {
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.SAVE');
    await flushPromises();

    expect(update).toHaveBeenCalledWith(
      expect.objectContaining({ version: 1, items: expect.any(Object) })
    );
    // Without this the organiser shows one menu and the bar beside it another,
    // until a reload.
    expect(setLayout).toHaveBeenCalled();
  });

  it('says so when saving fails instead of pretending it worked', async () => {
    update.mockRejectedValue(new Error('nope'));
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.SAVE');
    await flushPromises();

    expect(alerts).toHaveBeenCalledWith('SIDEBAR_ORGANISER.SAVE_FAILED');
  });
});
