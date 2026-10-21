import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/chatflow.json';
import QuestionEditor from '../editors/QuestionEditor.vue';
import ConditionEditor from '../editors/ConditionEditor.vue';
import WaitEditor from '../editors/WaitEditor.vue';
import RandomSplitEditor from '../editors/RandomSplitEditor.vue';
import GotoFlowEditor from '../editors/GotoFlowEditor.vue';
import TypingEditor from '../editors/TypingEditor.vue';
import ListActionEditor from '../editors/ListActionEditor.vue';

const labels = ref([{ id: 4, title: 'vip', color: '#f00' }]);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    name === 'labels/getLabels'
      ? labels
      : ref(model =>
          model === 'contact_attribute'
            ? [{ attribute_key: 'aniversario' }]
            : []
        ),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  messages: { pt_BR: ptBR },
});
const mountEditor = (component, props) =>
  mount(component, { props, global: { plugins: [i18n] } });
const lastPatch = wrapper => wrapper.emitted('update').at(-1)[0];

describe('editores dos blocos novos', () => {
  it('Pergunta: escolher e-mail já aponta para o e-mail do contato', async () => {
    const wrapper = mountEditor(QuestionEditor, {
      config: { field_type: 'text', save_to: {} },
    });
    await wrapper.find('[data-testid="question-type-email"]').trigger('click');
    expect(lastPatch(wrapper)).toEqual({
      field_type: 'email',
      save_to: { scope: 'contact', key: 'email' },
    });
    expect(wrapper.find('datalist').html()).toContain('aniversario');
  });

  it('Pergunta: gravar em atributo da conversa', async () => {
    const wrapper = mountEditor(QuestionEditor, {
      config: { save_to: { scope: 'conversation', key: '' } },
    });
    const input = wrapper.find('[data-testid="question-key"]');
    await input.setValue(' servico ');
    await input.trigger('change');
    expect(lastPatch(wrapper)).toEqual({
      save_to: { scope: 'conversation', key: 'servico' },
    });
  });

  it('Condição: adiciona regra de etiqueta e marca a etiqueta', async () => {
    const wrapper = mountEditor(ConditionEditor, { config: { rules: [] } });
    await wrapper.find('[data-testid="condition-add-label"]').trigger('click');
    expect(lastPatch(wrapper).rules).toEqual([
      { type: 'label', operator: 'has', label_ids: [] },
    ]);

    await wrapper.setProps({ config: { rules: lastPatch(wrapper).rules } });
    await wrapper
      .find('[data-testid="condition-rule-label"] button.border')
      .trigger('click');
    expect(lastPatch(wrapper).rules[0].label_ids).toEqual([4]);
  });

  it('Condição: regra de dia e hora nasce em horário comercial', async () => {
    const wrapper = mountEditor(ConditionEditor, { config: { rules: [] } });
    await wrapper
      .find('[data-testid="condition-add-schedule"]')
      .trigger('click');
    expect(lastPatch(wrapper).rules[0]).toMatchObject({
      weekdays: [1, 2, 3, 4, 5],
      from: '09:00',
      to: '18:00',
    });
  });

  it('Esperar: trocar o que fazer se a cliente responder', async () => {
    const wrapper = mountEditor(WaitEditor, {
      config: { mode: 'duration', amount: 1, unit: 'hours' },
    });
    await wrapper
      .find('[data-testid="wait-on-reply-branch"]')
      .trigger('change');
    expect(lastPatch(wrapper)).toEqual({ on_reply: 'branch' });
    await wrapper.find('[data-testid="wait-mode-until"]').trigger('click');
    expect(lastPatch(wrapper)).toEqual({ mode: 'until' });
  });

  it('A/B: mostra o total e adiciona o ramo C', async () => {
    const config = {
      branches: [
        { value: 'a', label: 'A', percent: 60 },
        { value: 'b', label: 'B', percent: 30 },
      ],
    };
    const wrapper = mountEditor(RandomSplitEditor, { config });
    expect(wrapper.find('[data-testid="split-total"]').text()).toBe(
      'Total: 90%'
    );
    await wrapper
      .findAll('button')
      .find(b => b.text().includes('Adicionar caminho'))
      .trigger('click');
    expect(lastPatch(wrapper).branches.at(-1)).toEqual({
      value: 'c',
      label: 'C',
      percent: 0,
    });
  });

  it('Ir para outro fluxo: não oferece o próprio fluxo', () => {
    const flows = [
      { id: 1, name: 'Este', status: 'draft' },
      { id: 2, name: 'Pós-venda', status: 'active' },
    ];
    const wrapper = mountEditor(GotoFlowEditor, {
      config: {},
      flows,
      currentFlowId: 1,
    });
    const options = wrapper.findAll('option').map(o => o.text());
    expect(options.some(o => o.includes('Pós-venda'))).toBe(true);
    expect(options.some(o => o.includes('Este'))).toBe(false);
  });

  it('Digitando: mostra os segundos', () => {
    const wrapper = mountEditor(TypingEditor, { config: { seconds: 5 } });
    expect(wrapper.text()).toContain('Pausa de 5 segundos');
  });

  it('Lista: avisa quando as listas ainda não existem', () => {
    const off = mountEditor(ListActionEditor, { config: {}, available: false });
    expect(off.find('[data-testid="list-unavailable"]').exists()).toBe(true);
    const on = mountEditor(ListActionEditor, {
      config: {},
      available: true,
      lists: [{ id: 1, name: 'VIP' }],
    });
    expect(on.find('[data-testid="list-unavailable"]').exists()).toBe(false);
    expect(on.text()).toContain('VIP');
  });
});
