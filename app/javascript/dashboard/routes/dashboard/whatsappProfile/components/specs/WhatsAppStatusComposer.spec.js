import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppStatusComposer from '../WhatsAppStatusComposer.vue';

const publishTextStatus = vi.fn();
const publishImageStatus = vi.fn();
const alerts = vi.fn();

vi.mock('dashboard/api/whatsappProfile', () => ({
  default: {
    publishTextStatus: (...args) => publishTextStatus(...args),
    publishImageStatus: (...args) => publishImageStatus(...args),
    publishVideoStatus: vi.fn(),
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
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template: '<input :value="modelValue" />',
  },
  TextArea: {
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template:
      '<textarea data-testid="status-text" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
  // O diálogo real usa <dialog> nativo. Aqui só precisamos do contrato que o
  // componente usa: abrir por ref, fechar por ref e emitir confirm.
  Dialog: {
    emits: ['confirm'],
    data: () => ({ isOpen: false }),
    methods: {
      open() {
        this.isOpen = true;
      },
      close() {
        this.isOpen = false;
      },
    },
    template:
      '<div v-if="isOpen" data-testid="confirm-dialog"><slot />' +
      '<button data-testid="confirm-publish" @click="$emit(\'confirm\')">confirm</button></div>',
  },
};

const mountComposer = () =>
  mount(WhatsAppStatusComposer, {
    props: { inboxId: 5 },
    global: { stubs },
  });

const writeText = async (wrapper, value) =>
  wrapper.find('[data-testid="status-text"]').setValue(value);

const clickPublish = async wrapper =>
  wrapper.find('[data-testid="publish-button"]').trigger('click');

describe('WhatsAppStatusComposer.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    publishTextStatus.mockResolvedValue({ data: { success: true } });
  });

  // Publicar é irreversível pelo painel. Um clique só no botão principal
  // mandaria o status para todos os contatos sem chance de recuar.
  it('never publishes on the first click', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');

    await clickPublish(wrapper);

    expect(publishTextStatus).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(true);
  });

  // A confirmação só vale se mostrar o que vai ao ar.
  it('shows the text that is about to go out inside the confirmation', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');
    await clickPublish(wrapper);

    expect(wrapper.find('[data-testid="publish-preview"]').text()).toContain(
      'Promoção hoje'
    );
  });

  it('publishes only after the operator confirms', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');
    await clickPublish(wrapper);

    await wrapper.find('[data-testid="confirm-publish"]').trigger('click');
    await flushPromises();

    expect(publishTextStatus).toHaveBeenCalledWith(5, {
      text: 'Promoção hoje',
      backgroundColor: expect.any(String),
    });
    expect(alerts).toHaveBeenCalledWith('WHATSAPP_PROFILE.STATUS.PUBLISHED');
  });

  // Perguntar "tem certeza?" sobre algo que nem sairia do lugar seria uma
  // pergunta falsa, então a recusa vem antes da confirmação.
  it('refuses an empty status without asking for confirmation', async () => {
    const wrapper = mountComposer();

    await clickPublish(wrapper);

    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'WHATSAPP_PROFILE.ERRORS.TEXT_REQUIRED'
    );
  });

  it('asks for a file before publishing an image status', async () => {
    const wrapper = mountComposer();

    await wrapper.find('[data-testid="kind-image"]').trigger('click');
    await clickPublish(wrapper);

    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'WHATSAPP_PROFILE.ERRORS.FILE_REQUIRED'
    );
  });

  // O operador precisa ler o motivo que veio do WhatsApp para saber se refaz
  // o status ou se o problema é a conexão.
  it('renders the reason WhatsApp refused the status', async () => {
    publishTextStatus.mockRejectedValue({
      response: { data: { error: 'session status is not WORKING' } },
    });

    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');
    await clickPublish(wrapper);
    await wrapper.find('[data-testid="confirm-publish"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'session status is not WORKING'
    );
  });
});
