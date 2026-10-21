import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/chatflow.json';
import ChatflowNode from '../ChatflowNode.vue';

vi.mock('@vue-flow/core', () => ({
  Handle: {
    props: ['id', 'type', 'position'],
    template: '<i class="handle" :data-handle="id" />',
  },
  Position: { Left: 'left', Right: 'right' },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  messages: { pt_BR: ptBR },
});
const render = (data, props = {}) =>
  mount(ChatflowNode, {
    props: { data, ...props },
    global: { plugins: [i18n] },
  });

describe('ChatflowNode', () => {
  it('condição mostra as duas portas nomeadas', () => {
    const wrapper = render({ kind: 'condition', config: { rules: [] } });
    expect(wrapper.find('[data-testid="node-exit-true"]').text()).toContain(
      'Sim (atende)'
    );
    expect(wrapper.find('[data-testid="node-exit-false"]').text()).toContain(
      'Senão'
    );
  });

  it('pergunta tem saída de resposta inválida', () => {
    const wrapper = render({
      kind: 'question',
      config: { text: 'Seu e-mail?' },
    });
    expect(wrapper.text()).toContain('Seu e-mail?');
    expect(wrapper.find('[data-testid="node-exit-invalid"]').exists()).toBe(
      true
    );
  });

  it('bloco linear tem uma porta só, sem rótulo; ir para fluxo nenhuma', () => {
    const typing = render({ kind: 'typing', config: { seconds: 2 } });
    expect(typing.findAll('[data-handle="default"]')).toHaveLength(1);
    const goto = render({ kind: 'goto_flow', config: {} });
    expect(goto.findAll('.handle')).toHaveLength(1); // só a entrada
  });

  it('mostra o funil da etapa quando ligado', () => {
    const wrapper = render(
      { kind: 'send_message', config: { text: 'Oi' } },
      { funnel: { entered: 12, rate: 75, waiting: 2 } }
    );
    const badge = wrapper.find('[data-testid="node-funnel"]').text();
    expect(badge).toContain('12');
    expect(badge).toContain('75% seguiram');
    expect(badge).toContain('2 aqui');
  });

  it('destaca a etapa onde a simulação parou', () => {
    const wrapper = render(
      { kind: 'menu', config: { options: [] } },
      { simulation: 'current' }
    );
    expect(wrapper.classes()).toContain('border-n-amber-8');
  });
});
