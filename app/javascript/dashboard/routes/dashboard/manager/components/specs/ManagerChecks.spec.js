import { mount, flushPromises } from '@vue/test-utils';
import ManagerChecks from '../ManagerChecks.vue';

const listChecks = vi.fn();
const updateCheck = vi.fn();

vi.mock('dashboard/api/aiManager', () => ({
  default: {
    listChecks: (...args) => listChecks(...args),
    updateCheck: (...args) => updateCheck(...args),
  },
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Spinner: true,
  Switch: {
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template:
      '<button role="switch" :aria-checked="String(modelValue)" @click="$emit(\'update:modelValue\', !modelValue)" />',
  },
};

const catalogue = [
  {
    key: 'promised_time_mismatch',
    title: 'Horário divergente',
    what_it_measures: 'Compara horário dito e horário salvo.',
    enabled: true,
  },
  {
    key: 'died_on_price',
    title: 'Morreu no preço',
    what_it_measures: 'Conversas que pararam no valor.',
    enabled: true,
  },
];

const mountChecks = () => mount(ManagerChecks, { global: { stubs } });

describe('ManagerChecks.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    listChecks.mockResolvedValue({
      data: { payload: catalogue.map(c => ({ ...c })) },
    });
    updateCheck.mockResolvedValue({ data: {} });
  });

  it('lists what the Manager looks for, in our own words', async () => {
    const wrapper = mountChecks();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="check-died_on_price"]').text()
    ).toContain('AI_MANAGER.CHECK.DIED_ON_PRICE.TITLE');
  });

  it('turns a check off through its own route', async () => {
    const wrapper = mountChecks();
    await flushPromises();

    await wrapper.find('[data-testid="toggle-died_on_price"]').trigger('click');
    await flushPromises();

    expect(updateCheck).toHaveBeenCalledWith('died_on_price', false);
  });

  // O interruptor volta sozinho quando o servidor recusa. Ficar na posição
  // nova seria a tela mentindo sobre o que o Gerente vai checar amanhã.
  it('puts the switch back when the change does not stick', async () => {
    updateCheck.mockRejectedValue({
      response: { data: { error: 'Não foi possível salvar' } },
    });

    const wrapper = mountChecks();
    await flushPromises();

    const toggle = wrapper.find('[data-testid="toggle-died_on_price"]');
    await toggle.trigger('click');
    await flushPromises();

    expect(
      wrapper
        .find('[data-testid="toggle-died_on_price"]')
        .attributes('aria-checked')
    ).toBe('true');
    expect(wrapper.find('[data-testid="checks-save-error"]').text()).toBe(
      'Não foi possível salvar'
    );
  });

  it('offers another go when the catalogue does not load', async () => {
    listChecks.mockRejectedValue({ message: 'Network Error' });

    const wrapper = mountChecks();
    await flushPromises();

    expect(wrapper.find('[data-testid="checks-error"]').text()).toContain(
      'Network Error'
    );

    listChecks.mockResolvedValue({ data: { payload: catalogue } });
    await wrapper.find('[data-testid="checks-retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="checks-error"]').exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="check-promised_time_mismatch"]').exists()
    ).toBe(true);
  });
});
