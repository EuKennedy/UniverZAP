import { mount, flushPromises } from '@vue/test-utils';
import ManagerRunNow from '../ManagerRunNow.vue';

const estimateRun = vi.fn();
const createRun = vi.fn();

vi.mock('dashboard/api/aiManager', () => ({
  default: {
    estimateRun: (...args) => estimateRun(...args),
    createRun: (...args) => createRun(...args),
  },
}));

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
};

const mountRun = () => mount(ManagerRunNow, { global: { stubs } });

describe('ManagerRunNow.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    estimateRun.mockResolvedValue({
      data: { credits_cents_brl: 320, conversations: 48 },
    });
    createRun.mockResolvedValue({ data: {} });
  });

  // O primeiro clique não gasta. Um botão que consome crédito na curiosidade
  // faz o cliente descobrir o valor na fatura, que é o pior lugar.
  it('prices the run before running it', async () => {
    const wrapper = mountRun();

    await wrapper.find('[data-testid="run-now"]').trigger('click');
    await flushPromises();

    expect(estimateRun).toHaveBeenCalled();
    expect(createRun).not.toHaveBeenCalled();

    const confirm = wrapper.find('[data-testid="run-confirm"]');
    expect(confirm.exists()).toBe(true);
    expect(confirm.text()).toContain('"conversations":"48"');
    expect(confirm.text()).toContain('3,20');
  });

  it('only spends on the second click', async () => {
    const wrapper = mountRun();

    await wrapper.find('[data-testid="run-now"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="run-confirm-action"]').trigger('click');
    await flushPromises();

    expect(createRun).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('ran')).toHaveLength(1);
    expect(wrapper.find('[data-testid="run-started"]').exists()).toBe(true);
  });

  it('lets the operator back out without spending', async () => {
    const wrapper = mountRun();

    await wrapper.find('[data-testid="run-now"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="run-cancel"]').trigger('click');

    expect(createRun).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="run-confirm"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="run-now"]').exists()).toBe(true);
  });

  // Sem conversa nova, rodar não produz sugestão nenhuma e ainda assim
  // custaria. A tela não oferece o gasto.
  it('does not offer to spend when there is nothing to analyse', async () => {
    estimateRun.mockResolvedValue({
      data: { credits_cents_brl: 0, conversations: 0 },
    });

    const wrapper = mountRun();
    await wrapper.find('[data-testid="run-now"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="run-confirm"]').text()).toContain(
      'AI_MANAGER.RUN.NOTHING_TO_ANALYSE'
    );
    expect(wrapper.find('[data-testid="run-confirm-action"]').exists()).toBe(
      false
    );
  });

  it('says the estimate failed and keeps the money in the account', async () => {
    estimateRun.mockRejectedValue({
      response: { data: { error: 'Serviço de crédito indisponível' } },
    });

    const wrapper = mountRun();
    await wrapper.find('[data-testid="run-now"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="run-error"]').text()).toBe(
      'Serviço de crédito indisponível'
    );
    expect(wrapper.find('[data-testid="run-confirm"]').exists()).toBe(false);
    expect(createRun).not.toHaveBeenCalled();
  });
});
