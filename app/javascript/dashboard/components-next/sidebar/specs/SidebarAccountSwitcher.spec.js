import { computed, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import SidebarAccountSwitcher from '../SidebarAccountSwitcher.vue';
import WorkspaceAPI from 'dashboard/api/workspace';

const accountId = ref(1);
const accounts = ref([]);
const shortcuts = {};
const push = vi.fn();

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId,
    currentAccount: computed(
      () => accounts.value.find(a => a.id === accountId.value) || {}
    ),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    ({
      getCurrentUser: computed(() => ({ accounts: accounts.value })),
      getUserAccounts: accounts,
      'globalConfig/get': computed(() => ({
        createNewAccountFromDashboard: true,
      })),
    })[name],
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: events => Object.assign(shortcuts, events),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/api/workspace', () => ({
  default: { summaries: vi.fn() },
}));

const account = (id, name, extra = {}) => ({
  id,
  name,
  role: 'administrator',
  cover_theme: null,
  cover_url: '',
  logo_url: '',
  vertical_name: null,
  ...extra,
});

const mountSwitcher = () =>
  mount(SidebarAccountSwitcher, {
    attachTo: document.body,
    // The global setup replaces the default stubs; without this the leave
    // transition waits for a transitionend that jsdom never fires.
    global: { stubs: { transition: true } },
  });

const optionNames = wrapper =>
  wrapper.findAll('[role="option"]').map(option => option.find('p').text());

const openPanel = async wrapper => {
  await wrapper.find('#sidebar-account-switcher').trigger('click');
  await flushPromises();
};

describe('SidebarAccountSwitcher', () => {
  let locationSpy;

  beforeEach(() => {
    Element.prototype.scrollIntoView = vi.fn();
    accountId.value = 1;
    accounts.value = [
      account(1, 'BEAUTY CENTER BH LOURDES - Estética Avançada', {
        vertical_name: 'Salão de beleza',
        cover_theme: 'orchid',
      }),
      account(2, 'biomelan'),
      account(3, 'lizzon', { role: 'agent' }),
    ];
    WorkspaceAPI.summaries.mockResolvedValue({
      data: {
        payload: [
          { account_id: 1, unread_notifications_count: 0 },
          { account_id: 2, unread_notifications_count: 4 },
        ],
      },
    });
    locationSpy = vi
      .spyOn(window, 'location', 'get')
      .mockReturnValue({ href: '' });
  });

  afterEach(() => {
    locationSpy.mockRestore();
    document.body.innerHTML = '';
  });

  it('opens a card per workspace with full name, role, vertical and current marker', async () => {
    const wrapper = mountSwitcher();
    await openPanel(wrapper);

    expect(optionNames(wrapper)).toEqual([
      'BEAUTY CENTER BH LOURDES - Estética Avançada',
      'biomelan',
      'lizzon',
    ]);
    const [beauty, biomelan, lizzon] = wrapper.findAll('[role="option"]');
    expect(beauty.attributes('aria-current')).toBe('true');
    expect(beauty.text()).toContain('Current');
    expect(beauty.text()).toContain('Salão de beleza');
    expect(beauty.text()).toContain('Administrator');
    expect(lizzon.text()).toContain('Agent');
    expect(biomelan.attributes('aria-current')).toBeUndefined();
  });

  it('shows the unread notifications of each workspace', async () => {
    const wrapper = mountSwitcher();
    await openPanel(wrapper);

    const [beauty, biomelan] = wrapper.findAll('[role="option"]');
    expect(biomelan.text()).toContain('4');
    expect(beauty.find('.bg-n-ruby-9').exists()).toBe(false);
  });

  it('switches with the arrows and Enter, and closes with Escape', async () => {
    const wrapper = mountSwitcher();
    await openPanel(wrapper);
    const list = wrapper.find('[role="listbox"]');

    await list.trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.find('[aria-selected="true"]').attributes('id')).toBe(
      'workspace-option-2'
    );

    await list.trigger('keydown', { key: 'Enter' });
    expect(window.location.href).toBe('/app/accounts/2/dashboard');

    await list.trigger('keydown', { key: 'Escape' });
    expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
  });

  it('jumps to a workspace by its number', async () => {
    const wrapper = mountSwitcher();
    await openPanel(wrapper);

    await wrapper.find('[role="listbox"]').trigger('keydown', { key: '3' });

    expect(window.location.href).toBe('/app/accounts/3/dashboard');
  });

  it('opens and closes with the keyboard shortcut', async () => {
    const wrapper = mountSwitcher();
    const event = { preventDefault: vi.fn() };

    shortcuts['$mod+Shift+KeyK'].action(event);
    await flushPromises();
    expect(wrapper.find('[role="listbox"]').exists()).toBe(true);

    shortcuts['$mod+Shift+KeyK'].action(event);
    await flushPromises();
    expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
  });

  it('searches by name or vertical once there are many workspaces', async () => {
    accounts.value = [
      ...accounts.value,
      account(4, 'nutriformulas', { vertical_name: 'Clínicas e consultórios' }),
      account(5, 'Ótica Visão'),
      account(6, 'Studio Bella Hair'),
    ];
    const wrapper = mountSwitcher();
    await openPanel(wrapper);

    const search = wrapper.find('input[type="search"]');
    await search.setValue('otica');
    expect(optionNames(wrapper)).toEqual(['Ótica Visão']);

    await search.setValue('clinicas');
    expect(optionNames(wrapper)).toEqual(['nutriformulas']);

    await search.setValue('zzz');
    expect(wrapper.text()).toContain('No workspace found');
  });

  it('hides the search with only a few workspaces', async () => {
    const wrapper = mountSwitcher();
    await openPanel(wrapper);

    expect(wrapper.find('input[type="search"]').exists()).toBe(false);
  });

  it('offers to customize the cover only to admins of the current workspace', async () => {
    const wrapper = mountSwitcher();
    await openPanel(wrapper);
    expect(wrapper.text()).toContain('Customize cover');

    accountId.value = 3;
    const agentView = mountSwitcher();
    await openPanel(agentView);
    expect(agentView.text()).not.toContain('Customize cover');
  });
});
