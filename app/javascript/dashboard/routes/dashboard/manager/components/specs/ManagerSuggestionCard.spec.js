import { mount } from '@vue/test-utils';
import ManagerSuggestionCard from '../ManagerSuggestionCard.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label', 'disabled'],
    emits: ['click'],
    template:
      '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
  RouterLink: {
    props: ['to'],
    template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
  },
};

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

const mountCard = (suggestion = aSuggestion(), props = {}) =>
  mount(ManagerSuggestionCard, {
    props: { suggestion, ...props },
    global: { stubs },
  });

describe('ManagerSuggestionCard.vue', () => {
  // Sem o trecho da conversa e o número que provocou o diagnóstico, aprovar é
  // confiar no parecer de um robô sobre o trabalho de outro robô.
  it('puts the conversation excerpt and the number on the card', () => {
    const wrapper = mountCard();

    expect(wrapper.find('[data-testid="evidence-excerpt"]').text()).toBe(
      'Fechado, te espero quinta às 14h.'
    );
    expect(wrapper.find('[data-testid="evidence-metric"]').text()).toBe(
      'minutes off: 120'
    );
    expect(
      wrapper.find('[data-testid="evidence-link"]').attributes('data-to')
    ).toContain('12');
  });

  // A rota de conversa do Chatwoot recebe o `display_id`, a sequência por conta,
  // e não a chave primária. Com a chave o botão abria a conversa de OUTRO
  // cliente, e a evidência é justamente o que sustenta o cartão.
  it('opens the conversation by its display id, never by the primary key', () => {
    const link = mountCard().find('[data-testid="evidence-link"]');

    expect(JSON.parse(link.attributes('data-to'))).toEqual({
      name: 'inbox_conversation',
      params: { conversation_id: 12 },
    });
  });

  // Conversa apagada depois da rodada: sem link é melhor que link quebrado.
  it('hides the link when there is no display id to open', () => {
    const wrapper = mountCard(
      aSuggestion({
        evidence: {
          conversation_id: 907,
          excerpt: 'Fechado, te espero quinta às 14h.',
          metric: 'minutes_off',
          value: 120,
        },
      })
    );

    expect(wrapper.find('[data-testid="evidence-link"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="evidence-excerpt"]').exists()).toBe(
      true
    );
  });

  it('shows what exactly would change', () => {
    const wrapper = mountCard();

    expect(wrapper.find('[data-testid="change-text"]').text()).toBe(
      'Confirmar o horário lendo a agenda antes de responder.'
    );
  });

  // Aprovar memória vale na hora, aprovar prompt abre uma disputa. Se as duas
  // ações tiverem a mesma cara, metade das aprovações é feita sem saber qual
  // das duas coisas acabou de acontecer.
  it('makes the memory target read as immediate', () => {
    const wrapper = mountCard(aSuggestion({ target: 'training' }));

    expect(wrapper.find('[data-testid="target-chip"]').text()).toBe(
      'AI_MANAGER.CARD.TARGET.TRAINING'
    );
    expect(wrapper.find('[data-testid="target-effect"]').text()).toBe(
      'AI_MANAGER.CARD.TARGET.TRAINING_EFFECT'
    );
    expect(wrapper.find('[data-testid="approve"]').text()).toBe(
      'AI_MANAGER.CARD.APPROVE_TRAINING'
    );
  });

  it('makes the prompt target read as a contest it might lose', () => {
    const wrapper = mountCard(aSuggestion({ target: 'prompt_version' }));

    expect(wrapper.find('[data-testid="target-chip"]').text()).toBe(
      'AI_MANAGER.CARD.TARGET.PROMPT'
    );
    expect(wrapper.find('[data-testid="target-effect"]').text()).toBe(
      'AI_MANAGER.CARD.TARGET.PROMPT_EFFECT'
    );
    expect(wrapper.find('[data-testid="approve"]').text()).toBe(
      'AI_MANAGER.CARD.APPROVE_PROMPT'
    );
  });

  // Crítico não pode depender de cor: a palavra e o ícone carregam a mesma
  // informação para quem não separa vermelho de âmbar.
  it('spells out critical severity instead of only colouring it', () => {
    const badge = mountCard().find('[data-testid="severity-badge"]');

    expect(badge.text()).toBe('AI_MANAGER.CARD.SEVERITY.CRITICAL');
    expect(badge.find('.i-lucide-alert-triangle').exists()).toBe(true);
  });

  it('marks a normal suggestion with its own word and icon', () => {
    const badge = mountCard(aSuggestion({ severity: 'low' })).find(
      '[data-testid="severity-badge"]'
    );

    expect(badge.text()).toBe('AI_MANAGER.CARD.SEVERITY.NORMAL');
    expect(badge.find('.i-lucide-alert-triangle').exists()).toBe(false);
  });

  it('emits approve without asking anything else', async () => {
    const wrapper = mountCard();

    await wrapper.find('[data-testid="approve"]').trigger('click');

    expect(wrapper.emitted('approve')).toHaveLength(1);
  });

  // Dispensa sem motivo esvazia a fila sem ninguém aprender nada, e a mesma
  // sugestão volta na semana seguinte.
  it('refuses to dismiss until a reason is typed', async () => {
    const wrapper = mountCard();

    await wrapper.find('[data-testid="dismiss"]').trigger('click');
    expect(wrapper.find('[data-testid="dismiss-panel"]').exists()).toBe(true);

    const confirm = wrapper.find('[data-testid="dismiss-confirm"]');
    expect(confirm.attributes('disabled')).toBeDefined();

    await confirm.trigger('click');
    expect(wrapper.emitted('dismiss')).toBeUndefined();

    await wrapper.find('[data-testid="dismiss-reason"]').setValue('   ');
    expect(
      wrapper.find('[data-testid="dismiss-confirm"]').attributes('disabled')
    ).toBeDefined();

    await wrapper
      .find('[data-testid="dismiss-reason"]')
      .setValue('  o cliente remarcou por telefone  ');
    await wrapper.find('[data-testid="dismiss-confirm"]').trigger('click');

    expect(wrapper.emitted('dismiss')[0]).toEqual([
      'o cliente remarcou por telefone',
    ]);
  });

  // Verificação que o servidor invente ainda aparece, com o título dele, em
  // vez de sumir da fila por falta de tradução.
  it('falls back to the server title for an unknown check', () => {
    const wrapper = mountCard(
      aSuggestion({ check_key: 'novo_check', title: 'Algo novo apareceu' })
    );

    expect(wrapper.find('[data-testid="headline"]').text()).toBe(
      'Algo novo apareceu'
    );
  });

  it('uses our own copy for a check we already know', () => {
    expect(mountCard().find('[data-testid="headline"]').text()).toBe(
      'AI_MANAGER.CHECK.PROMISED_TIME_MISMATCH.TITLE'
    );
  });
});
