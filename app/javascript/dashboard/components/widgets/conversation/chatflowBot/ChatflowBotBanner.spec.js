import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/chatflow.json';
import ChatflowsAPI from 'dashboard/api/chatflows';
import ChatflowBotBanner from './ChatflowBotBanner.vue';

vi.mock('dashboard/api/chatflows', () => ({
  default: {
    conversationState: vi.fn(),
    pauseConversation: vi.fn(),
    resumeConversation: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const selectedChat = ref({ id: 42, messages: [] });
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => selectedChat,
}));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  messages: { pt_BR: ptBR },
});

const running = {
  paused: false,
  execution: {
    id: 1,
    status: 'waiting_input',
    chatflow_name: 'Agendamento',
    node_name: 'Qual serviço?',
    node_kind: 'question',
  },
};

describe('ChatflowBotBanner', () => {
  beforeEach(() => vi.clearAllMocks());

  it('sem fluxo nem pausa, não aparece', async () => {
    ChatflowsAPI.conversationState.mockResolvedValue({
      data: { paused: false, execution: null },
    });
    const wrapper = mount(ChatflowBotBanner, { global: { plugins: [i18n] } });
    await flushPromises();
    expect(wrapper.find('[data-testid="chatflow-bot-banner"]').exists()).toBe(
      false
    );
  });

  it('mostra o fluxo em andamento e pausa com um clique', async () => {
    ChatflowsAPI.conversationState.mockResolvedValue({ data: running });
    ChatflowsAPI.pauseConversation.mockResolvedValue({
      data: {
        paused: true,
        paused_by: 'Ana',
        execution: { ...running.execution, status: 'paused' },
      },
    });
    const wrapper = mount(ChatflowBotBanner, { global: { plugins: [i18n] } });
    await flushPromises();

    expect(wrapper.text()).toContain(
      'Robô em andamento: Agendamento · Qual serviço?'
    );
    await wrapper.find('[data-testid="chatflow-bot-toggle"]').trigger('click');
    await flushPromises();

    expect(ChatflowsAPI.pauseConversation).toHaveBeenCalledWith(42);
    expect(wrapper.text()).toContain('Ana assumiu a conversa');
    expect(
      wrapper.find('[data-testid="chatflow-bot-toggle"]').attributes('label')
    ).toBe('Retomar robô');
  });

  it('retoma quando está pausado', async () => {
    ChatflowsAPI.conversationState.mockResolvedValue({
      data: { paused: true, execution: null },
    });
    ChatflowsAPI.resumeConversation.mockResolvedValue({
      data: { paused: false, execution: null },
    });
    const wrapper = mount(ChatflowBotBanner, { global: { plugins: [i18n] } });
    await flushPromises();

    await wrapper.find('[data-testid="chatflow-bot-toggle"]').trigger('click');
    await flushPromises();
    expect(ChatflowsAPI.resumeConversation).toHaveBeenCalledWith(42);
    expect(wrapper.find('[data-testid="chatflow-bot-banner"]').exists()).toBe(
      false
    );
  });
});
