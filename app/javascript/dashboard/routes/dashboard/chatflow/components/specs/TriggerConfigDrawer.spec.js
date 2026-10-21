import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/chatflow.json';
import TriggerConfigDrawer from '../TriggerConfigDrawer.vue';

vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
const labels = ref([{ id: 4, title: 'carrinho-abandonado', color: '#f00' }]);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    name === 'labels/getLabels'
      ? labels
      : ref(name === 'getCurrentAccountId' ? 1 : []),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  messages: { pt_BR: ptBR },
});
const mountDrawer = (chatflow, options = {}) =>
  mount(TriggerConfigDrawer, {
    props: { chatflow: { id: 1, trigger_config: {}, ...chatflow }, options },
    global: { plugins: [i18n] },
  });
const save = async wrapper => {
  await wrapper
    .findAll('button')
    .find(b => b.text() === ptBR.CHATFLOW.TRIGGER.SAVE)
    .trigger('click');
  return wrapper.emitted('save').at(-1)[0];
};

describe('TriggerConfigDrawer — gatilhos novos', () => {
  it('etiqueta adicionada grava as etiquetas escolhidas', async () => {
    const wrapper = mountDrawer({ trigger_type: 'label_added' });
    await wrapper.find('[data-testid="trigger-label-4"]').trigger('click');
    const payload = await save(wrapper);
    expect(payload.trigger_type).toBe('label_added');
    expect(payload.trigger_config.label_ids).toEqual([4]);
  });

  it('data grava tipo, dias e hora', async () => {
    const wrapper = mountDrawer({
      trigger_type: 'date',
      trigger_config: {
        date: { kind: 'after_appointment', days: '2', hour: '11' },
      },
    });
    expect(wrapper.find('[data-testid="trigger-date"]').exists()).toBe(true);
    const payload = await save(wrapper);
    expect(payload.trigger_config.date).toMatchObject({
      kind: 'after_appointment',
      days: 2,
      hour: 11,
    });
  });

  it('lista avisa quando as listas não existem', () => {
    const wrapper = mountDrawer(
      { trigger_type: 'list_entered' },
      { lists_available: false }
    );
    expect(
      wrapper.find('[data-testid="trigger-lists-unavailable"]').exists()
    ).toBe(true);
  });

  it('pausar quando o atendente responde vem ligado e pode ser desligado', async () => {
    const wrapper = mountDrawer({ trigger_type: 'keyword' });
    expect((await save(wrapper)).trigger_config.pause_on_agent_reply).toBe(
      true
    );
    await wrapper
      .find('[data-testid="trigger-pause-on-agent"]')
      .setValue(false);
    expect((await save(wrapper)).trigger_config.pause_on_agent_reply).toBe(
      false
    );
  });
});
