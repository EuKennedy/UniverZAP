import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppProfileCard from '../WhatsAppProfileCard.vue';

const profile = vi.fn();
const updateName = vi.fn();
const alerts = vi.fn();

vi.mock('dashboard/api/whatsappProfile', () => ({
  default: {
    profile: (...args) => profile(...args),
    updateName: (...args) => updateName(...args),
    updateAbout: vi.fn(),
    updatePicture: vi.fn(),
    deletePicture: vi.fn(),
  },
}));

vi.mock('dashboard/helper/uploadHelper', () => ({
  uploadFile: vi.fn().mockResolvedValue({ blobId: 'blob-1' }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: (...a) => alerts(...a) }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Input: {
    props: ['modelValue', 'label', 'message'],
    emits: ['update:modelValue'],
    template:
      '<div><input data-testid="name-input" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />' +
      '<span data-testid="name-message">{{ message }}</span></div>',
  },
  TextArea: {
    props: ['modelValue', 'message'],
    emits: ['update:modelValue'],
    template: '<textarea :value="modelValue" />',
  },
  Spinner: true,
};

const mountCard = () =>
  mount(WhatsAppProfileCard, { props: { inboxId: 5 }, global: { stubs } });

const saveName = async wrapper => {
  const save = wrapper
    .findAll('button')
    .find(button => button.text() === 'WHATSAPP_PROFILE.PROFILE.SAVE');
  await save.trigger('click');
  await flushPromises();
};

describe('WhatsAppProfileCard.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    profile.mockResolvedValue({
      data: { name: 'Loja da Ana', picture: 'https://cdn.test/p.jpg' },
    });
    updateName.mockResolvedValue({ data: { name: 'Loja da Ana' } });
  });

  it('shows the profile of the selected connection', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(profile).toHaveBeenCalledWith(5);
    expect(wrapper.find('img').attributes('src')).toBe(
      'https://cdn.test/p.jpg'
    );
    expect(wrapper.find('[data-testid="name-input"]').element.value).toBe(
      'Loja da Ana'
    );
  });

  it('saves the name and confirms it', async () => {
    const wrapper = mountCard();
    await flushPromises();
    await wrapper.find('[data-testid="name-input"]').setValue('Loja da Ana 2');

    await saveName(wrapper);

    expect(updateName).toHaveBeenCalledWith(5, 'Loja da Ana 2');
    expect(alerts).toHaveBeenCalledWith('WHATSAPP_PROFILE.PROFILE.NAME_SAVED');
  });

  // O motivo real vindo da API, e não um "algo deu errado": é ele que diz se o
  // operador reescreve o nome ou se precisa reconectar o número.
  it('renders the reason the API refused the new name', async () => {
    updateName.mockRejectedValue({
      response: { data: { error: 'name is too long' } },
    });

    const wrapper = mountCard();
    await flushPromises();
    await wrapper.find('[data-testid="name-input"]').setValue('x'.repeat(300));

    await saveName(wrapper);

    expect(wrapper.find('[data-testid="name-message"]').text()).toBe(
      'name is too long'
    );
    expect(alerts).not.toHaveBeenCalled();
  });

  it('shows why the profile could not be read', async () => {
    profile.mockRejectedValue({
      response: { data: { error: 'sessão parada' } },
    });

    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('[data-testid="profile-load-error"]').text()).toBe(
      'sessão parada'
    );
  });
});
