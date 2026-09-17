import { mount, flushPromises } from '@vue/test-utils';
import GuiaLauncher from '../GuiaLauncher.vue';

const getWikiAssistant = vi.fn();
const createThread = vi.fn();
const sendThreadMessage = vi.fn();

vi.mock('dashboard/api/athenas', () => ({
  default: {
    getWikiAssistant: (...args) => getWikiAssistant(...args),
    createThread: (...args) => createThread(...args),
    sendThreadMessage: (...args) => sendThreadMessage(...args),
  },
}));

const updateUISettings = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: { value: {} }, updateUISettings }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/useOnboardingState', () => ({
  useOnboardingState: () => ({
    setLastStepIndex: vi.fn().mockResolvedValue(undefined),
    resetDismiss: vi.fn(),
  }),
}));

const routeName = { value: 'athenas_assistants_index' };
vi.mock('vue-router', () => ({
  useRoute: () => ({
    get name() {
      return routeName.value;
    },
  }),
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

vi.mock('dashboard/components-next/onboarding/onboardingSteps', () => ({
  ONBOARDING_TOUR_EVENTS: { START: 'tour:start' },
}));

const stubs = { Icon: true };
const openPanelAndAsk = async (wrapper, text) => {
  await wrapper.find('[data-testid="guia-launcher"]').trigger('click');
  await wrapper.find('textarea').setValue(text);
  await wrapper.find('textarea').trigger('keydown.enter');
  await flushPromises();
};

describe('GuiaLauncher.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    routeName.value = 'athenas_assistants_index';
    getWikiAssistant.mockResolvedValue({ data: { id: 7, name: 'Guia' } });
    createThread.mockResolvedValue({
      data: {
        id: 1,
        messages: [
          {
            id: 10,
            role: 'assistant',
            content: 'Configurações → Caixas de entrada',
          },
        ],
      },
    });
  });

  it('mostra a estrela', () => {
    const wrapper = mount(GuiaLauncher, { global: { stubs } });

    expect(wrapper.find('[data-testid="guia-launcher"]').exists()).toBe(true);
  });

  // O "?" que ela substitui só aparecia para administrador, e quem trava no dia
  // a dia é a atendente — justamente quem não tem a quem perguntar.
  it('some só nas telas de login e setup', () => {
    routeName.value = 'login';
    const wrapper = mount(GuiaLauncher, { global: { stubs } });

    expect(wrapper.find('[data-testid="guia-launcher"]').exists()).toBe(false);
  });

  it('resolve o Guia da conta antes de abrir a primeira thread', async () => {
    const wrapper = mount(GuiaLauncher, { global: { stubs } });

    await openPanelAndAsk(wrapper, 'como conecto o whatsapp?');

    expect(getWikiAssistant).toHaveBeenCalled();
    expect(createThread).toHaveBeenCalledWith(
      expect.objectContaining({
        assistantId: 7,
        initialMessage: 'como conecto o whatsapp?',
      })
    );
  });

  it('mostra a resposta que voltou', async () => {
    const wrapper = mount(GuiaLauncher, { global: { stubs } });

    await openPanelAndAsk(wrapper, 'onde?');

    expect(wrapper.text()).toContain('Configurações → Caixas de entrada');
  });
});
