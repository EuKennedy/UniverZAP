import { mount, flushPromises } from '@vue/test-utils';
import ManagerIndex from '../ManagerIndex.vue';

const overview = vi.fn();
const listSuggestions = vi.fn();
const approveSuggestion = vi.fn();
const dismissSuggestion = vi.fn();

vi.mock('dashboard/api/aiManager', () => ({
  default: {
    overview: (...args) => overview(...args),
    listSuggestions: (...args) => listSuggestions(...args),
    approveSuggestion: (...args) => approveSuggestion(...args),
    dismissSuggestion: (...args) => dismissSuggestion(...args),
    estimateRun: vi.fn(),
    createRun: vi.fn(),
    listChecks: vi.fn(),
    updateCheck: vi.fn(),
  },
}));

// A chave é a asserção, mas os parâmetros viajam junto: a diferença entre
// "faltam 18 conversas" e "faltam 30" é a única informação do estado de dado
// insuficiente, e um teste cego para os parâmetros passaria com o número
// errado na tela.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

const stubs = {
  Button: {
    props: ['label', 'disabled'],
    emits: ['click'],
    template:
      '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
  Spinner: true,
  ManagerRunNow: { template: '<div data-testid="run-now-stub" />' },
  ManagerChecks: { template: '<div data-testid="checks-stub" />' },
  ManagerSuggestionCard: {
    props: ['suggestion', 'isBusy'],
    emits: ['approve', 'dismiss'],
    template:
      '<div data-testid="card">{{ suggestion.id }}' +
      '<button data-testid="card-approve" @click="$emit(\'approve\')" />' +
      '<button data-testid="card-dismiss" @click="$emit(\'dismiss\', \'o cliente remarcou por telefone\')" />' +
      '</div>',
  },
};

const mountPage = () => mount(ManagerIndex, { global: { stubs } });

const anOverview = (extra = {}) => ({
  scores: {
    reliability: { value: 92.4, previous: 88, change: 4.4 },
    conversion: { value: 31, previous: 35, change: -4 },
    cost: { value: 1840, previous: 1600, change: 15 },
  },
  agents: [{ id: 1, name: 'Athenas', scores: {} }],
  last_run_at: 1755400000,
  next_run_at: 1755486400,
  pending_count: 0,
  data_sufficiency: { enough: true, analysed: 240, needed: 30 },
  ...extra,
});

const aSuggestion = (extra = {}) => ({
  id: 42,
  ai_assistant_id: 1,
  agent_name: 'Athenas',
  check_key: 'promised_time_mismatch',
  title: 'Horário divergente',
  rationale: 'O agente disse 14h e a agenda gravou 16h.',
  severity: 'critical',
  evidence: {
    conversation_id: 907,
    conversation_display_id: 12,
    excerpt: 'Fechado, te espero quinta às 14h.',
    metric: 'minutes_off',
    value: 120,
  },
  target: 'training',
  proposed: 'Confirmar o horário lendo a agenda antes de responder.',
  status: 'pending',
  created_at: 1755400000,
  ...extra,
});

describe('ManagerIndex.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    overview.mockResolvedValue({ data: anOverview() });
    listSuggestions.mockResolvedValue({ data: { payload: [] } });
  });

  // Fila vazia é boa notícia, e a tela precisa dizer isso junto com quando o
  // Gerente passou por aqui. Sem a data, vazio não se distingue de parado.
  it('celebrates the empty queue and says when it last ran', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="empty-queue"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('AI_MANAGER.QUEUE.EMPTY_TITLE');
    expect(wrapper.find('[data-testid="empty-last-run"]').text()).toContain(
      'AI_MANAGER.LAST_RUN'
    );
    expect(wrapper.find('[data-testid="run-schedule"]').text()).toContain(
      'AI_MANAGER.SCHEDULE_BOTH'
    );
  });

  it('asks the backend only for the pending queue', async () => {
    mountPage();
    await flushPromises();

    expect(listSuggestions).toHaveBeenCalledWith({ status: 'pending' });
  });

  // Nota calculada em cima de doze conversas é chute com cara de medição. Sem
  // dado suficiente, as três notas não aparecem: some a nota, entra a conta.
  it('replaces the scores with the honest gap when data is short', async () => {
    overview.mockResolvedValue({
      data: anOverview({
        data_sufficiency: { enough: false, analysed: 12, needed: 30 },
      }),
    });

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="data-gap"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="score-strip"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="data-gap-remaining"]').text()).toContain(
      '"n":"18"'
    );
  });

  it('shows the three scores separately once there is enough data', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="score-reliability"]').text()).toContain(
      '92,4%'
    );
    expect(wrapper.find('[data-testid="trend-reliability"]').text()).toContain(
      '↑'
    );
    expect(wrapper.find('[data-testid="score-conversion"]').text()).toContain(
      '31%'
    );
    expect(wrapper.find('[data-testid="score-cost"]').text()).toContain(
      '18,40'
    );
    expect(wrapper.find('[data-testid="data-gap"]').exists()).toBe(false);
  });

  it('approves the suggestion and takes it out of the queue', async () => {
    listSuggestions.mockResolvedValue({ data: { payload: [aSuggestion()] } });
    approveSuggestion.mockResolvedValue({ data: {} });

    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-testid="card-approve"]').trigger('click');
    await flushPromises();

    expect(approveSuggestion).toHaveBeenCalledWith(42);
    expect(wrapper.find('[data-testid="card"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="empty-queue"]').exists()).toBe(true);
  });

  it('sends the reason along when the card dismisses', async () => {
    listSuggestions.mockResolvedValue({ data: { payload: [aSuggestion()] } });
    dismissSuggestion.mockResolvedValue({ data: {} });

    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-testid="card-dismiss"]').trigger('click');
    await flushPromises();

    expect(dismissSuggestion).toHaveBeenCalledWith(
      42,
      'o cliente remarcou por telefone'
    );
    expect(wrapper.find('[data-testid="card"]').exists()).toBe(false);
  });

  // Aprovação que falhou não pode sumir com o card: o operador acharia que
  // aplicou e o agente continuaria errando a mesma coisa.
  it('keeps the card and explains when approving fails', async () => {
    listSuggestions.mockResolvedValue({ data: { payload: [aSuggestion()] } });
    approveSuggestion.mockRejectedValue({
      response: { data: { error: 'Crédito insuficiente' } },
    });

    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-testid="card-approve"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="action-error"]').text()).toBe(
      'Crédito insuficiente'
    );
    expect(wrapper.find('[data-testid="card"]').exists()).toBe(true);
  });

  it('shows why the screen could not load and offers another go', async () => {
    overview.mockRejectedValue({
      response: { data: { error: 'O Gerente está fora do ar' } },
    });

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="load-error"]').text()).toContain(
      'O Gerente está fora do ar'
    );

    overview.mockResolvedValue({ data: anOverview() });
    await wrapper.find('[data-testid="retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="load-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="empty-queue"]').exists()).toBe(true);
  });

  it('keeps the checks catalogue behind its own tab', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="checks-stub"]').exists()).toBe(false);

    await wrapper.find('[data-testid="tab-checks"]').trigger('click');

    expect(wrapper.find('[data-testid="checks-stub"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="empty-queue"]').exists()).toBe(false);
  });
});
