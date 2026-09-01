import { mount } from '@vue/test-utils';
import ManagerConversationCard from '../ManagerConversationCard.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  RouterLink: {
    props: ['to'],
    template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
  },
};

const aFinding = (extra = {}) => ({
  id: 7,
  case_key: 'cliente_esperando',
  severity: 'critical',
  title: 'Cliente esperando resposta',
  detail: 'Fernanda escreveu há 30 horas e ninguém respondeu depois disso.',
  excerpt: 'Consigo horário sábado?',
  author: 'none',
  source: 'triage',
  conversation_id: 907,
  conversation_display_id: 12,
  contact_name: 'Fernanda',
  occurred_at: new Date(Date.now() - 30 * 3600 * 1000).toISOString(),
  value_brl: 0,
  answered_after: false,
  metadata: {},
  ...extra,
});

const build = extra =>
  mount(ManagerConversationCard, {
    props: { finding: aFinding(extra) },
    global: { stubs },
  });

describe('ManagerConversationCard', () => {
  it('mostra a frase antes do trecho, porque é a conclusão que se lê varrendo', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="detail"]').text()).toContain('Fernanda');
    expect(wrapper.find('[data-testid="excerpt"]').text()).toBe(
      'Consigo horário sábado?'
    );
  });

  // `conversation_display_id` e não `conversation_id`: a URL do Chatwoot usa a
  // sequência POR CONTA, e a chave primária abriria a conversa de OUTRO
  // cliente. É o clique inteiro da feature apontando para o lugar errado.
  it('aponta o link para o display_id e nunca para a chave primária', () => {
    const wrapper = build();

    const to = JSON.parse(wrapper.find('a').attributes('data-to'));
    expect(to.params.conversation_id).toBe(12);
  });

  it('não mostra trecho quando não existe, em vez de deixar aspas vazias', () => {
    const wrapper = build({ excerpt: null });

    expect(wrapper.find('[data-testid="excerpt"]').exists()).toBe(false);
  });

  it('mostra o dinheiro parado só quando existe', () => {
    expect(build().find('[data-testid="value"]').exists()).toBe(false);
    expect(
      build({ value_brl: 900 }).find('[data-testid="value"]').text()
    ).toContain('900');
  });

  // Um achado de terça continua no banco depois que alguém respondeu na quarta.
  // Ele não some, porque o histórico foi pedido para ficar gravado, mas precisa
  // apagar: mantê-lo aceso manda atender de novo quem já foi atendido.
  it('apaga o cartão que já foi respondido em vez de sumir com ele', () => {
    const wrapper = build({ answered_after: true });

    expect(wrapper.find('[data-testid="answered"]').exists()).toBe(true);
    expect(wrapper.find('a').classes()).toContain('opacity-55');
  });

  it('diz de onde a conclusão veio, para separar o que foi contado do que foi lido', () => {
    expect(build().find('[data-testid="source"]').text()).toBe(
      'AI_MANAGER.MODERATION.SOURCE.TRIAGE'
    );
    expect(
      build({ source: 'reading' }).find('[data-testid="source"]').text()
    ).toBe('AI_MANAGER.MODERATION.SOURCE.READING');
  });

  it('rotula quem falou por último, que é o filtro que o operador usa', () => {
    expect(
      build({ author: 'agent' }).find('[data-testid="author"]').text()
    ).toBe('AI_MANAGER.MODERATION.AUTHOR.AGENT');
  });

  // Gravidade não pode depender só da cor: quem não separa vermelho de âmbar
  // precisa da palavra e do ícone para varrer a lista.
  it('separa gravidade por palavra e por ícone, não só por cor', () => {
    const critical = build({ severity: 'critical' });
    const medium = build({ severity: 'medium' });

    expect(critical.find('[data-testid="severity"]').text()).toBe(
      'AI_MANAGER.MODERATION.SEVERITY.CRITICAL'
    );
    expect(critical.find('.i-lucide-alert-triangle').exists()).toBe(true);
    expect(medium.find('.i-lucide-alert-triangle').exists()).toBe(false);
  });
});
