import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/chatflow.json';
import ChatflowsAPI from 'dashboard/api/chatflows';
import ChatflowSimulator from '../ChatflowSimulator.vue';

vi.mock('dashboard/api/chatflows', () => ({ default: { simulate: vi.fn() } }));

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  messages: { pt_BR: ptBR },
});

const reply = data => ({
  data: { transcript: [], finished: false, visited_node_ids: [], ...data },
});

describe('ChatflowSimulator', () => {
  beforeEach(() => ChatflowsAPI.simulate.mockReset());

  it('começa o fluxo, mostra o roteiro e destaca as etapas', async () => {
    ChatflowsAPI.simulate.mockResolvedValue(
      reply({
        transcript: [{ type: 'bot', text: 'Qual seu e-mail?', node_id: 2 }],
        visited_node_ids: [1, 2],
        current_node_id: 2,
      })
    );
    const wrapper = mount(ChatflowSimulator, {
      props: { chatflowId: 9 },
      global: { plugins: [i18n] },
    });
    await flushPromises();

    expect(ChatflowsAPI.simulate).toHaveBeenCalledWith(
      9,
      expect.objectContaining({ inputs: [] })
    );
    expect(wrapper.find('[data-testid="simulator-bot"]').text()).toBe(
      'Qual seu e-mail?'
    );
    expect(wrapper.emitted('highlight').at(-1)[0]).toEqual({
      visited: ['1', '2'],
      current: '2',
    });
    expect(wrapper.text()).toContain('Nada é enviado à cliente');
  });

  it('cada resposta reenvia todas as falas com a mesma semente', async () => {
    ChatflowsAPI.simulate.mockResolvedValue(reply({}));
    const wrapper = mount(ChatflowSimulator, {
      props: { chatflowId: 9 },
      global: { plugins: [i18n] },
    });
    await flushPromises();
    const seed = ChatflowsAPI.simulate.mock.calls[0][1].seed;

    await wrapper
      .find('[data-testid="simulator-input"]')
      .setValue('ana@gmail.com');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    await wrapper.find('[data-testid="simulator-input"]').setValue('sim');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(ChatflowsAPI.simulate.mock.calls.at(-1)[1]).toEqual({
      inputs: ['ana@gmail.com', 'sim'],
      seed,
    });
  });

  it('eventos, dados capturados e fim do fluxo', async () => {
    ChatflowsAPI.simulate.mockResolvedValue(
      reply({
        transcript: [
          { type: 'event', event: 'waited' },
          { type: 'event', event: 'skipped_webhook' },
        ],
        answers: { email: 'ana@gmail.com' },
        finished: true,
      })
    );
    const wrapper = mount(ChatflowSimulator, {
      props: { chatflowId: 9 },
      global: { plugins: [i18n] },
    });
    await flushPromises();

    const events = wrapper
      .findAll('[data-testid="simulator-event"]')
      .map(e => e.text());
    expect(events).toEqual([
      'Espera concluída (simulada)',
      'Webhook não chamado na simulação',
    ]);
    expect(wrapper.find('[data-testid="simulator-answers"]').text()).toContain(
      'email: ana@gmail.com'
    );
    expect(
      wrapper.find('[data-testid="simulator-input"]').attributes('disabled')
    ).toBeDefined();
  });

  it('avisa quando o fluxo não tem etapa inicial', async () => {
    ChatflowsAPI.simulate.mockResolvedValue(reply({ error: 'no_start_node' }));
    const wrapper = mount(ChatflowSimulator, {
      props: { chatflowId: 9 },
      global: { plugins: [i18n] },
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="simulator-error"]').text()).toContain(
      'etapa inicial'
    );
  });
});
