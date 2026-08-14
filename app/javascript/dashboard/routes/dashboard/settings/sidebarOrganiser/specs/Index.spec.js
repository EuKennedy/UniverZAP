import { mount, flushPromises } from '@vue/test-utils';
import Index from '../Index.vue';

const update = vi.fn();
const alerts = vi.fn();
const setLayout = vi.fn();

const menu = [
  { name: 'Inbox', label: 'Caixa de entrada' },
  { name: 'Report', label: 'Relatórios' },
  {
    name: 'Conversation',
    label: 'Conversas',
    children: [{ name: 'All', label: 'Todas' }],
  },
];

vi.mock('dashboard/api/sidebarLayout', () => ({
  default: { update: (...args) => update(...args) },
}));
vi.mock('dashboard/composables', () => ({ useAlert: (...a) => alerts(...a) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useSidebarLayout', () => ({
  useSidebarLayout: () => ({
    layout: { value: {} },
    menu: { value: menu },
    setLayout: (...a) => setLayout(...a),
  }),
}));

const stubs = {
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

describe('SidebarOrganiser', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    update.mockResolvedValue({ data: { layout: { version: 1 } } });
  });

  it('starts with no groups and every item loose', () => {
    const wrapper = mountScreen();

    expect(wrapper.text()).toContain('SIDEBAR_ORGANISER.NO_GROUPS');
    expect(wrapper.findAll('select')).toHaveLength(2);
  });

  // A native group inside a custom one would be a third level, which the
  // sidebar does not render — so it is never offered as movable.
  it('does not offer a native group as something to move', () => {
    const wrapper = mountScreen();

    const loose = wrapper.find('section:last-of-type').text();
    expect(loose).toContain('Relatórios');
    expect(loose).not.toContain('Conversas');
  });

  it('creates a group and lets an item be moved into it', async () => {
    const wrapper = mountScreen();
    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.ADD_GROUP');

    const select = wrapper.findAll('select')[1];
    await select.setValue(select.findAll('option')[1].element.value);

    expect(wrapper.text()).toContain('SIDEBAR_ORGANISER.NEW_GROUP');
  });

  // Deleting a group must never take its items down with it.
  it('sends the items home when a group is deleted', async () => {
    const wrapper = mountScreen();
    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.ADD_GROUP');
    const select = wrapper.findAll('select')[1];
    await select.setValue(select.findAll('option')[1].element.value);

    await clickByLabel(wrapper, 'i-lucide-trash-2');

    expect(wrapper.findAll('select')).toHaveLength(2);
  });

  it('saves the whole layout and updates the live sidebar', async () => {
    const wrapper = mountScreen();
    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.ADD_GROUP');
    await clickByLabel(wrapper, 'SIDEBAR_ORGANISER.SAVE');
    await flushPromises();

    expect(update).toHaveBeenCalledWith(
      expect.objectContaining({ version: 1, groups: expect.any(Array) })
    );
    // Without this the organiser would show one menu and the bar beside it
    // another, until a reload.
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
