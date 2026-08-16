import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppProfileIndex from '../WhatsAppProfileIndex.vue';

const inboxes = vi.fn();
const push = vi.fn();

vi.mock('dashboard/api/whatsappProfile', () => ({
  default: {
    inboxes: (...args) => inboxes(...args),
    profile: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));

// A chave é a asserção: cada texto desta tela responde a uma situação
// diferente, e um teste que casasse com a prosa passaria mostrando a frase
// errada para o operador.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Select: {
    props: ['options', 'modelValue'],
    emits: ['update:modelValue'],
    template:
      '<select data-testid="inbox-select" @change="$emit(\'update:modelValue\', Number($event.target.value))">' +
      '<option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option></select>',
  },
  Spinner: true,
  WhatsAppProfileCard: {
    props: ['inboxId'],
    template: '<div data-testid="profile-card">{{ inboxId }}</div>',
  },
  WhatsAppStatusComposer: {
    props: ['inboxId'],
    template: '<div data-testid="status-composer">{{ inboxId }}</div>',
  },
};

const mountPage = () => mount(WhatsAppProfileIndex, { global: { stubs } });

describe('WhatsAppProfileIndex.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    inboxes.mockResolvedValue({ data: { payload: [] } });
  });

  // Sem conexão WAHA não existe número para editar. Um seletor vazio deixaria
  // o operador clicando à toa, sem saber que falta um passo anterior.
  it('explains what is missing instead of showing an empty picker', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="empty-state"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inbox-select"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="profile-card"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('WHATSAPP_PROFILE.EMPTY.TITLE');
  });

  it('sends the operator to the connection screen from the empty state', async () => {
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('button').trigger('click');

    expect(push).toHaveBeenCalledWith({ name: 'settings_inbox_new' });
  });

  // Com uma conexão só, um seletor seria enfeite.
  it('names the single connection without offering a choice', async () => {
    inboxes.mockResolvedValue({ data: { payload: [{ id: 7, name: 'Loja' }] } });

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="inbox-select"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Loja');
    expect(wrapper.find('[data-testid="profile-card"]').text()).toBe('7');
  });

  it('hands the chosen connection to both cards', async () => {
    inboxes.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'Loja' },
          { id: 9, name: 'Suporte' },
        ],
      },
    });

    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="profile-card"]').text()).toBe('7');

    await wrapper.find('[data-testid="inbox-select"]').setValue('9');
    await flushPromises();

    expect(wrapper.find('[data-testid="profile-card"]').text()).toBe('9');
    expect(wrapper.find('[data-testid="status-composer"]').text()).toBe('9');
  });

  it('shows the reason the list could not be loaded', async () => {
    inboxes.mockRejectedValue({
      response: { data: { error: 'WAHA fora do ar' } },
    });

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="load-error"]').text()).toBe(
      'WAHA fora do ar'
    );
  });
});
