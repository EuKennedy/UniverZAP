import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Index from '../Index.vue';

const update = vi.fn();
const alerts = vi.fn();
const setLayout = vi.fn();

const menu = [
  {
    name: 'Inbox',
    label: 'Caixa de entrada',
    icon: 'i-lucide-inbox',
    to: { name: 'inbox_view', params: { accountId: 7 } },
  },
  {
    name: 'Kanban',
    label: 'Kanban',
    icon: 'i-lucide-kanban',
    to: { name: 'kanban_overview', params: { accountId: 7 } },
  },
  {
    name: 'Conversation',
    label: 'Conversas',
    children: [
      {
        name: 'All',
        label: 'Todas',
        to: { name: 'home', params: { accountId: 7 } },
      },
    ],
  },
];

// Real refs, because the screen watches the menu: the sidebar publishes it a
// tick after this mounts, and a plain object would never exercise that.
const savedLayout = ref({});
const builtMenu = ref(menu);

vi.mock('dashboard/api/sidebarLayout', () => ({
  default: { update: (...args) => update(...args) },
}));
vi.mock('dashboard/composables', () => ({ useAlert: (...a) => alerts(...a) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useSidebarLayout', () => ({
  useSidebarLayout: () => ({
    layout: savedLayout,
    menu: builtMenu,
    setLayout: (...a) => setLayout(...a),
  }),
}));

// Dragging itself belongs to vuedraggable. What matters here is that the lists
// it moves things between are wired to the right state, and that the payload
// built from them says what the screen is showing.
const stubs = {
  Draggable: {
    props: ['modelValue'],
    template:
      '<ul><li v-for="(e, i) in modelValue" :key="i"><slot name="item" :element="e" /></li></ul>',
  },
  Button: {
    props: ['label', 'icon'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label || icon }}</button>',
  },
  Icon: true,
};

const mountScreen = () => mount(Index, { global: { stubs } });
const buttonsFor = (wrapper, text) =>
  wrapper.findAll('button').filter(button => button.text() === text);
const clickByLabel = (wrapper, label) =>
  buttonsFor(wrapper, label)[0].trigger('click');
const placeholders = wrapper =>
  wrapper.findAll('input').map(input => input.attributes('placeholder'));
const savePayload = async wrapper => {
  await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.SAVE');
  await flushPromises();
  return update.mock.calls[0][0];
};

describe('SidebarOrganiser', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    savedLayout.value = {};
    update.mockResolvedValue({ data: { layout: { version: 2 } } });
  });

  it('shows every item by its own name', () => {
    const shown = placeholders(mountScreen());

    expect(shown).toContain('Caixa de entrada');
    expect(shown).toContain('Kanban');
  });

  // The tabs anybody actually wants to file away are the ones that carry other
  // tabs, and the previous screen refused to offer exactly those — so Conversas,
  // Contatos and Relatórios could never be organised at all.
  it('offers a native group too, and says it brings its tabs', () => {
    const wrapper = mountScreen();

    expect(placeholders(wrapper)).toContain('Conversas');

    const badge = wrapper.find('[title="SIDEBAR_ORGANISER.CARRIES_TABS"]');
    expect(badge.exists()).toBe(true);
    expect(badge.text()).toBe('1');
  });

  it('saves the order the items are shown in', async () => {
    const payload = await savePayload(mountScreen());

    expect(payload.version).toBe(2);
    expect(payload.order).toEqual(['Inbox', 'Kanban', 'Conversation']);
  });

  it('rebuilds the lists from a layout that was already saved', () => {
    savedLayout.value = {
      version: 2,
      order: ['g_1', 'Inbox'],
      groups: [{ id: 'g_1', label: 'Gestão', items: ['Kanban'] }],
      items: { Kanban: { label: 'Funis' } },
    };

    // v-model writes the DOM property, so the attribute selector would miss it.
    const values = mountScreen()
      .findAll('input')
      .map(input => input.element.value);

    expect(values).toContain('Gestão');
    expect(values).toContain('Funis');
  });

  it('creates a group ready to receive items', async () => {
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.ADD_GROUP');

    expect(wrapper.text()).toContain('SIDEBAR_ORGANISER.DROP_HERE');
  });

  // Deleting a group must never take its items down with it, and must not
  // exile them to the bottom of a list somebody just finished arranging.
  it('leaves the items where the group was when it is deleted', async () => {
    savedLayout.value = {
      version: 2,
      order: ['Inbox', 'g_1', 'Conversation'],
      groups: [{ id: 'g_1', label: 'Gestão', items: ['Kanban'] }],
      items: {},
    };
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'i-lucide-trash-2');
    const payload = await savePayload(wrapper);

    expect(payload.groups).toEqual([]);
    expect(payload.order).toEqual(['Inbox', 'Kanban', 'Conversation']);
  });

  describe('the home screen', () => {
    // Stored as a route name, never a path: one global setting is read by
    // people in different accounts, and a path carries somebody else's id.
    it('records the route without the account it was picked in', async () => {
      const wrapper = mountScreen();

      await buttonsFor(wrapper, 'i-lucide-house-plus')[1].trigger('click');
      const payload = await savePayload(wrapper);

      expect(payload.home).toEqual({
        item: 'Kanban',
        route: 'kanban_overview',
        params: {},
      });
    });

    // A heading has no route of its own, so "open on Conversas" can only mean
    // the first screen it leads to.
    it('lands a native group on the first screen it opens', async () => {
      const wrapper = mountScreen();

      await buttonsFor(wrapper, 'i-lucide-house-plus')[2].trigger('click');
      const payload = await savePayload(wrapper);

      expect(payload.home.item).toBe('Conversation');
      expect(payload.home.route).toBe('home');
    });

    it('goes back to the default landing when the same item is picked again', async () => {
      const wrapper = mountScreen();

      await buttonsFor(wrapper, 'i-lucide-house-plus')[1].trigger('click');
      await buttonsFor(wrapper, 'i-lucide-house')[0].trigger('click');
      const payload = await savePayload(wrapper);

      expect(payload.home).toBeUndefined();
    });

    it('holds one at a time, so a second choice replaces the first', async () => {
      const wrapper = mountScreen();

      await buttonsFor(wrapper, 'i-lucide-house-plus')[1].trigger('click');
      await buttonsFor(wrapper, 'i-lucide-house-plus')[0].trigger('click');
      const payload = await savePayload(wrapper);

      expect(payload.home.item).toBe('Inbox');
    });
  });

  it('writes down only what was actually changed', async () => {
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'i-lucide-eye');
    const payload = await savePayload(wrapper);

    // A rule per menu item would grow a permanent row for every tab we ever
    // ship, and "positioned here" would stop being distinguishable from
    // "never touched".
    expect(payload.items).toEqual({ Inbox: { hidden: true } });
  });

  it('updates the live sidebar as well as the server', async () => {
    await savePayload(mountScreen());

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

  it('puts everything back the way the product ships it', async () => {
    savedLayout.value = {
      version: 2,
      order: ['g_1'],
      groups: [{ id: 'g_1', label: 'Gestão', items: ['Kanban', 'Inbox'] }],
      items: { Inbox: { hidden: true, label: 'Entrada' } },
      home: { item: 'Kanban', route: 'kanban_overview', params: {} },
    };
    const wrapper = mountScreen();

    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.RESET');
    const payload = await savePayload(wrapper);

    expect(payload).toEqual({
      version: 2,
      order: ['Inbox', 'Kanban', 'Conversation'],
      groups: [],
      items: {},
    });
  });
});
