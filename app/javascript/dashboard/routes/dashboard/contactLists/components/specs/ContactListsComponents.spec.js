import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ContactListsAPI from 'dashboard/api/contactLists';
import contactLists from 'dashboard/i18n/locale/pt_BR/contactLists.json';
import broadcast from 'dashboard/i18n/locale/pt_BR/broadcast.json';
import ImportCsvDialog from '../ImportCsvDialog.vue';
import AudienceListsPicker from '../../../broadcasts/components/AudienceListsPicker.vue';
import ColdContactsConfirm from '../../../broadcasts/components/ColdContactsConfirm.vue';
import GroupListCard from '../../../conversation/GroupListCard.vue';

vi.mock('dashboard/api/contactLists', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    groups: vi.fn(),
    importCsv: vi.fn(),
    extractGroup: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: { pt_BR: { ...contactLists, ...broadcast } },
});

const DialogStub = {
  template:
    '<div><slot /><button data-testid="confirm" @click="$emit(\'confirm\')" /></div>',
  methods: { open() {}, close() {} },
};
const ButtonStub = {
  props: ['label', 'isLoading'],
  emits: ['click'],
  template:
    '<button :data-loading="isLoading" @click="$emit(\'click\')">{{ label }}</button>',
};

const global = {
  plugins: [i18n],
  stubs: {
    Dialog: DialogStub,
    Button: ButtonStub,
    'router-link': { template: '<a><slot /></a>' },
  },
};

beforeEach(() => vi.clearAllMocks());

describe('ColdContactsConfirm', () => {
  it('não aparece sem contatos frios', () => {
    const wrapper = mount(ColdContactsConfirm, { props: { count: 0 }, global });
    expect(wrapper.find('[data-testid="cold-contacts"]').exists()).toBe(false);
  });

  it('mostra a contagem e emite a confirmação', async () => {
    const wrapper = mount(ColdContactsConfirm, { props: { count: 3 }, global });

    expect(wrapper.text()).toContain(
      '3 contatos deste público nunca falaram com o salão'
    );
    expect(wrapper.text()).toContain(
      'Confirmo: enviar para estes 3 contatos que nunca falaram com o salão'
    );
    await wrapper.find('[data-testid="cold-contacts-confirm"]').setValue(true);
    expect(wrapper.emitted('change')).toEqual([[true]]);
  });
});

describe('AudienceListsPicker', () => {
  it('lista as listas da conta e alterna a seleção', async () => {
    ContactListsAPI.get.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'VIP', source: 'group', members_count: 12 },
          { id: 8, name: 'Março', source: 'csv', members_count: 4 },
        ],
      },
    });
    const wrapper = mount(AudienceListsPicker, {
      props: { modelValue: [8] },
      global,
    });
    await flushPromises();

    expect(wrapper.text()).toContain('VIP');
    await wrapper.find('[data-testid="audience-list-7"]').trigger('click');
    await wrapper.find('[data-testid="audience-list-8"]').trigger('click');

    expect(wrapper.emitted('update:modelValue')).toEqual([[[8, 7]], [[]]]);
  });
});

describe('ImportCsvDialog', () => {
  it('envia o texto com "nunca falaram" marcado por padrão', async () => {
    ContactListsAPI.importCsv.mockResolvedValue({
      data: { added: 2, created: 1, invalid: 0 },
    });
    const wrapper = mount(ImportCsvDialog, { props: { listId: 5 }, global });
    wrapper.vm.open();
    await wrapper
      .find('[data-testid="import-csv-content"]')
      .setValue('Ana;31988881111\n31977772222');

    expect(wrapper.text()).toContain('Ana;31988881111');
    await wrapper.find('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    expect(ContactListsAPI.importCsv).toHaveBeenCalledWith(5, {
      content: 'Ana;31988881111\n31977772222',
      cold: true,
    });
    expect(wrapper.emitted('imported')).toHaveLength(1);
  });
});

describe('GroupListCard', () => {
  it('sem lista, oferece extrair e chama a API com a conversa', async () => {
    ContactListsAPI.groups.mockResolvedValue({
      data: { payload: [{ display_id: 42, list_id: null }] },
    });
    ContactListsAPI.extractGroup.mockResolvedValue({
      data: { id: 9, status: 'importing', members_count: 0 },
    });
    const wrapper = mount(GroupListCard, {
      props: { conversationId: 42 },
      global,
    });
    await flushPromises();

    const button = wrapper.find('[data-testid="group-list-extract"]');
    expect(button.text()).toBe('Extrair participantes');
    await button.trigger('click');
    await flushPromises();

    expect(ContactListsAPI.extractGroup).toHaveBeenCalledWith(42);
    expect(wrapper.text()).toContain('Extraindo…');
    wrapper.unmount();
  });

  it('com lista, mostra os membros e oferece atualizar e abrir', async () => {
    ContactListsAPI.groups.mockResolvedValue({
      data: { payload: [{ display_id: 42, list_id: 9 }] },
    });
    ContactListsAPI.show.mockResolvedValue({
      data: { id: 9, status: 'ready', members_count: 23 },
    });
    const wrapper = mount(GroupListCard, {
      props: { conversationId: 42 },
      global,
    });
    await flushPromises();

    expect(wrapper.text()).toContain('23 membros');
    expect(wrapper.text()).toContain('Atualizar a partir do grupo');
    await wrapper
      .findAll('button')
      .find(node => node.text() === 'Abrir lista')
      .trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'contact_lists_show',
      params: { listId: 9 },
    });
  });
});
