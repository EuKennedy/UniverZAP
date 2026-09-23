import { mutations } from '../../chatflows';

describe('chatflows mutations', () => {
  describe('#patchActiveChatflow', () => {
    const withGraph = () => ({
      active: {
        chatflow: { id: 7, status: 'draft', name: 'SAC' },
        nodes: [{ id: 1 }, { id: 2 }],
        edges: [{ id: 10 }],
      },
    });

    // Ativar devolvia o resumo do fluxo e nada era commitado no fluxo ATIVO, então
    // o selo continuava "Rascunho" até alguém dar F5.
    it('atualiza o fluxo ativo', () => {
      const state = withGraph();

      mutations.patchActiveChatflow(state, {
        id: 7,
        status: 'active',
        name: 'SAC',
      });

      expect(state.active.chatflow.status).toBe('active');
    });

    // Entrar em modo de teste passava o resumo por setActiveChatflow, e
    // `nodes: data.nodes || []` apagava o canvas inteiro.
    it('preserva as etapas e as ligações já carregadas', () => {
      const state = withGraph();

      mutations.patchActiveChatflow(state, { id: 7, test_mode: true });

      expect(state.active.nodes).toHaveLength(2);
      expect(state.active.edges).toHaveLength(1);
    });

    // Um fluxo respondendo por outro sobrescreveria a tela aberta.
    it('ignora o resumo de um fluxo diferente do que está aberto', () => {
      const state = withGraph();

      mutations.patchActiveChatflow(state, { id: 99, status: 'active' });

      expect(state.active.chatflow.id).toBe(7);
      expect(state.active.chatflow.status).toBe('draft');
    });

    it('não explode quando não há fluxo aberto', () => {
      const state = { active: { chatflow: null, nodes: [], edges: [] } };

      expect(() =>
        mutations.patchActiveChatflow(state, { id: 7, status: 'active' })
      ).not.toThrow();
    });
  });
});
