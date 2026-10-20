import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppStatusComposer from '../WhatsAppStatusComposer.vue';

const save = vi.fn();
const suggest = vi.fn();
const alerts = vi.fn();

vi.mock('dashboard/api/whatsappStatus', () => ({
  default: {
    save: (...args) => save(...args),
    suggest: (...args) => suggest(...args),
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
    emits: ['update:modelValue', 'enter'],
    template:
      '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
  TextArea: {
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template:
      '<textarea data-testid="status-text" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
  Checkbox: {
    props: ['modelValue'],
    emits: ['change'],
    template:
      '<input type="checkbox" :checked="modelValue" @change="$emit(\'change\')" />',
  },
  StatusTemplatesMenu: {
    props: ['current'],
    emits: ['apply'],
    template:
      "<button data-testid=\"apply-template\" @click=\"$emit('apply', { body: 'Agenda aberta', background_color: '#8E44AD', font: 2 })\">t</button>",
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

const INBOXES = [
  { id: 5, name: 'Loja' },
  { id: 8, name: 'Filial' },
];

const mountComposer = (props = {}) =>
  mount(WhatsAppStatusComposer, {
    props: { inboxes: INBOXES, defaultInboxId: 5, ...props },
    global: { stubs },
  });

const writeText = async (wrapper, value) =>
  wrapper.find('[data-testid="status-text"]').setValue(value);

const clickPublish = async wrapper =>
  wrapper.find('[data-testid="publish-button"]').trigger('click');

const confirm = async wrapper => {
  await wrapper.find('[data-testid="confirm-publish"]').trigger('click');
  await flushPromises();
};

describe('WhatsAppStatusComposer.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    save.mockResolvedValue({ data: { id: 1, status: 'publishing' } });
  });

  // Publicar é irreversível pelo painel. Um clique só no botão principal
  // mandaria o status para todos os contatos sem chance de recuar.
  it('never publishes on the first click', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');

    await clickPublish(wrapper);

    expect(save).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(true);
  });

  // A confirmação só vale se mostrar o que vai ao ar e onde.
  it('shows the text and the connections inside the confirmation', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');
    await wrapper.find('[data-testid="connection-8"] input').trigger('change');
    await clickPublish(wrapper);

    const preview = wrapper.find('[data-testid="publish-preview"]');
    expect(preview.text()).toContain('Promoção hoje');
    expect(
      wrapper.findAll('[data-testid="confirm-connection"]').map(n => n.text())
    ).toEqual(['Loja', 'Filial']);
  });

  it('publishes to every chosen connection only after confirming', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');
    await wrapper.find('[data-testid="connection-8"] input').trigger('change');
    await wrapper.find('[data-testid="font-3"]').trigger('click');
    await clickPublish(wrapper);
    await confirm(wrapper);

    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        intent: 'publish',
        kind: 'text',
        body: 'Promoção hoje',
        font: 3,
        inboxIds: [5, 8],
      })
    );
    expect(alerts).toHaveBeenCalledWith(
      'WHATSAPP_PROFILE.STATUS.SAVED.PUBLISH'
    );
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('schedules for the chosen time', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Sábado tem horário');
    await wrapper.find('[data-testid="when-later"]').trigger('click');
    await wrapper
      .find('[data-testid="schedule-at"]')
      .setValue('2099-01-02T09:30');
    await clickPublish(wrapper);
    await confirm(wrapper);

    const payload = save.mock.calls[0][0];
    expect(payload.intent).toBe('schedule');
    expect(new Date(payload.scheduledAt).getTime()).toBe(
      new Date('2099-01-02T09:30').getTime()
    );
  });

  it('refuses a schedule without a future time before asking', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Sábado tem horário');
    await wrapper.find('[data-testid="when-later"]').trigger('click');
    await clickPublish(wrapper);

    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'WHATSAPP_PROFILE.ERRORS.SCHEDULE_REQUIRED'
    );
  });

  // Rascunho não vai a lugar nenhum, então não precisa de confirmação.
  it('saves a draft straight away', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'ideia');
    await wrapper.find('[data-testid="draft-button"]').trigger('click');
    await flushPromises();

    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({ intent: 'draft' })
    );
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

  it('asks for a connection before publishing', async () => {
    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção');
    await wrapper.find('[data-testid="connection-5"] input').trigger('change');
    await clickPublish(wrapper);

    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'WHATSAPP_PROFILE.ERRORS.CONNECTION_REQUIRED'
    );
  });

  it('asks for a file before publishing an image status', async () => {
    const wrapper = mountComposer();

    await wrapper.find('[data-testid="kind-image"]').trigger('click');
    await clickPublish(wrapper);

    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'WHATSAPP_PROFILE.ERRORS.FILE_REQUIRED'
    );
  });

  it('fills the text with the AI suggestion', async () => {
    suggest.mockResolvedValue({
      data: { text: 'Sábado com horários livres!' },
    });
    const wrapper = mountComposer();

    await wrapper.find('[data-testid="suggest-toggle"]').trigger('click');
    await wrapper
      .find('[data-testid="suggest-prompt"]')
      .setValue('agenda de sábado');
    await wrapper.find('[data-testid="suggest-button"]').trigger('click');
    await flushPromises();

    expect(suggest).toHaveBeenCalledWith({
      prompt: 'agenda de sábado',
      body: '',
      kind: 'text',
    });
    expect(wrapper.find('[data-testid="status-text"]').element.value).toBe(
      'Sábado com horários livres!'
    );
  });

  it('applies a template to the text and the look', async () => {
    const wrapper = mountComposer();
    await wrapper.find('[data-testid="apply-template"]').trigger('click');
    await clickPublish(wrapper);
    await confirm(wrapper);

    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        body: 'Agenda aberta',
        backgroundColor: '#8E44AD',
        font: 2,
      })
    );
  });

  it('edits an existing draft in place', async () => {
    const wrapper = mountComposer({
      editingPost: {
        id: 42,
        kind: 'text',
        body: 'Rascunho antigo',
        background_color: '#1F7A3D',
        font: 1,
        inbox_ids: [8],
        status: 'draft',
      },
    });
    await clickPublish(wrapper);
    await confirm(wrapper);

    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 42,
        body: 'Rascunho antigo',
        inboxIds: [8],
      })
    );
  });

  // O operador precisa ler o motivo que veio do servidor para saber o que
  // corrigir.
  it('renders the reason the status was refused', async () => {
    save.mockRejectedValue({
      response: { data: { message: 'Inbox ids is invalid' } },
    });

    const wrapper = mountComposer();
    await writeText(wrapper, 'Promoção hoje');
    await clickPublish(wrapper);
    await confirm(wrapper);

    expect(wrapper.find('[data-testid="publish-error"]').text()).toBe(
      'Inbox ids is invalid'
    );
  });
});
