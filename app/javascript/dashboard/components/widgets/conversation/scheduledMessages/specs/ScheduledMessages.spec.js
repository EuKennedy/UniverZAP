import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import ScheduleMessageDialog from '../ScheduleMessageDialog.vue';
import ScheduledMessagesBanner from '../ScheduledMessagesBanner.vue';

vi.mock('dashboard/api/scheduledMessages', () => ({
  default: {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    cancel: vi.fn(),
    bestTime: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const selectedChat = ref(null);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => selectedChat,
}));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: {
    pt_BR: {
      SCHEDULED_MESSAGES: {
        BANNER: {
          PENDING: 'Mensagem agendada para {when}',
          CANCELLED: {
            CUSTOMER_REPLIED: 'Não enviada: a cliente escreveu antes',
          },
        },
        DIALOG: { PREVIEW: 'Ela vai receber:', MISSING: 'Vazio: {names}' },
      },
    },
  },
});

const DialogStub = {
  template:
    '<div><slot /><button data-testid="confirm" @click="$emit(\'confirm\')" /></div>',
  methods: { open() {}, close() {} },
};

const scheduled = (overrides = {}) => ({
  id: 1,
  conversation_id: 42,
  content: 'Oi {primeiro_nome}, tudo bem?',
  status: 'scheduled',
  send_at: new Date(2026, 9, 21, 9, 0).toISOString(),
  cancel_if_reply: true,
  updated_at: new Date().toISOString(),
  ...overrides,
});

describe('ScheduleMessageDialog', () => {
  const mountDialog = () =>
    mount(ScheduleMessageDialog, {
      props: {
        conversationId: 42,
        contact: { name: 'Mariana Souza' },
        conversation: { custom_attributes: { servico: 'Escova' } },
      },
      global: { plugins: [i18n], stubs: { Dialog: DialogStub } },
    });

  beforeEach(() => {
    ScheduledMessagesAPI.bestTime.mockResolvedValue({
      data: { hour: 14, at: new Date(2026, 9, 21, 14, 0).toISOString() },
    });
    ScheduledMessagesAPI.create.mockResolvedValue({ data: scheduled() });
  });

  it('traz o texto digitado, mostra a prévia e agenda pelo atalho', async () => {
    const wrapper = mountDialog();
    wrapper.vm.open({ content: 'Oi {primeiro_nome}, sua {servico}?' });
    await flushPromises();

    expect(
      wrapper.find('[data-testid="schedule-message-preview"]').text()
    ).toContain('Oi Mariana, sua Escova?');
    expect(wrapper.find('[data-testid="shortcut-BEST_TIME"]').exists()).toBe(
      true
    );

    await wrapper.find('[data-testid="shortcut-TOMORROW_9"]').trigger('click');
    await wrapper.find('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    const [conversationId, payload] = ScheduledMessagesAPI.create.mock.calls[0];
    expect(conversationId).toBe(42);
    expect(payload.content).toBe('Oi {primeiro_nome}, sua {servico}?');
    expect(payload.cancel_if_reply).toBe(true);
    expect(new Date(payload.send_at).getHours()).toBe(9);
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('avisa quando uma variável fica vazia para a cliente', async () => {
    const wrapper = mountDialog();
    wrapper.vm.open({ content: 'Com {profissional}' });
    await flushPromises();

    expect(wrapper.text()).toContain('Vazio: {profissional}');
  });
});

describe('ScheduledMessagesBanner', () => {
  const mountBanner = () =>
    mount(ScheduledMessagesBanner, {
      global: {
        plugins: [i18n],
        stubs: {
          ScheduleMessageDialog: true,
          NextButton: { template: '<button @click="$emit(\'click\')" />' },
        },
        directives: { tooltip: {} },
      },
    });

  it('mostra o pendente e o que foi cancelado porque a cliente respondeu', async () => {
    selectedChat.value = { id: 42, messages: [], meta: { sender: {} } };
    ScheduledMessagesAPI.list.mockResolvedValue({
      data: {
        payload: [
          scheduled(),
          scheduled({
            id: 2,
            status: 'cancelled',
            cancel_reason: 'customer_replied',
          }),
        ],
      },
    });
    const wrapper = mountBanner();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="scheduled-message-pending"]').text()
    ).toContain('Mensagem agendada para');
    expect(
      wrapper.find('[data-testid="scheduled-message-issue"]').text()
    ).toContain('a cliente escreveu antes');
  });

  it('cancela pelo indicador', async () => {
    selectedChat.value = { id: 43, messages: [], meta: { sender: {} } };
    ScheduledMessagesAPI.list.mockResolvedValue({
      data: { payload: [scheduled({ id: 5 })] },
    });
    ScheduledMessagesAPI.cancel.mockResolvedValue({
      data: scheduled({ id: 5, status: 'cancelled', cancel_reason: 'manual' }),
    });
    const wrapper = mountBanner();
    await flushPromises();

    await wrapper
      .find('[data-testid="scheduled-message-cancel"]')
      .trigger('click');
    await flushPromises();

    expect(ScheduledMessagesAPI.cancel).toHaveBeenCalledWith(5);
    expect(
      wrapper.find('[data-testid="scheduled-message-pending"]').exists()
    ).toBe(false);
  });
});
