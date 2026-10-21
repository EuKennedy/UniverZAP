import ptBR from 'dashboard/i18n/locale/pt_BR/chatflow.json';
import en from 'dashboard/i18n/locale/en/chatflow.json';
import { createI18n } from 'vue-i18n';
import {
  KIND_META,
  PALETTE_GROUPS,
  paletteFor,
  defaultConfigFor,
  nodeHandles,
  nodeSummary,
  splitTotal,
  nextBranchValue,
} from '../nodeKinds';

const { t } = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
}).global;

const node = (kind, config = {}) => ({ kind, config });
const handlesOf = (kind, config) =>
  nodeHandles(node(kind, config), t).map(h => h.handle);

describe('nodeKinds', () => {
  it('a paleta cobre todos os blocos, em grupos', () => {
    const kinds = PALETTE_GROUPS.flatMap(group => paletteFor(group)).map(
      i => i.kind
    );
    expect(kinds.sort()).toEqual(Object.keys(KIND_META).sort());
  });

  it('todo bloco tem nome nos dois idiomas', () => {
    Object.keys(KIND_META).forEach(kind => {
      expect(ptBR.CHATFLOW.NODE.KIND[kind.toUpperCase()]).toBeTruthy();
      expect(en.CHATFLOW.NODE.KIND[kind.toUpperCase()]).toBeTruthy();
    });
  });

  it('configuração inicial é uma cópia nova a cada bloco', () => {
    const first = defaultConfigFor('random_split');
    first.branches[0].percent = 90;
    expect(defaultConfigFor('random_split').branches[0].percent).toBe(50);
    expect(defaultConfigFor('wait')).toMatchObject({
      on_reply: 'stop',
      respect_window: true,
    });
  });

  describe('saídas (o contrato com o motor)', () => {
    it('pergunta: válida e inválida', () => {
      expect(handlesOf('question')).toEqual(['default', 'invalid']);
    });

    it('condição: verdadeiro e falso', () => {
      expect(handlesOf('condition')).toEqual(['true', 'false']);
    });

    it('espera: só ganha "Respondeu" quando configurada para isso', () => {
      expect(handlesOf('wait', { on_reply: 'stop' })).toEqual(['default']);
      expect(handlesOf('wait', { on_reply: 'branch' })).toEqual([
        'default',
        'replied',
      ]);
    });

    it('A/B: uma saída por ramo, com o percentual no rótulo', () => {
      const exits = nodeHandles(
        node('random_split', {
          branches: [
            { value: 'a', label: 'Cupom', percent: 70 },
            { value: 'b', label: 'Frete', percent: 30 },
          ],
        }),
        t
      );
      expect(exits.map(e => e.handle)).toEqual(['a', 'b']);
      expect(exits[0].label).toBe('Cupom · 70%');
    });

    it('ir para outro fluxo e fim não têm saída; digitando e lista têm uma', () => {
      expect(handlesOf('goto_flow')).toEqual([]);
      expect(handlesOf('end_flow')).toEqual([]);
      expect(handlesOf('typing')).toEqual(['default']);
      expect(handlesOf('list_action')).toEqual(['default']);
    });

    it('cada porta nomeada tem a classe da bolinha escrita por extenso', () => {
      nodeHandles(node('condition'), t).forEach(exit => {
        expect(exit.handleClass).toBe(`!${exit.dot}`);
      });
    });
  });

  describe('resumo do cartão', () => {
    it('espera por tempo e até uma data', () => {
      expect(nodeSummary(node('wait', { amount: 2, unit: 'days' }), t)).toBe(
        'Espera 2 dias'
      );
      expect(
        nodeSummary(
          node('wait', { mode: 'until', until: '2026-12-24T18:00' }),
          t
        )
      ).toBe('Espera até 2026-12-24 18:00');
    });

    it('ir para outro fluxo mostra o nome do destino', () => {
      const flows = [{ id: 3, name: 'Pós-venda' }];
      expect(
        nodeSummary(node('goto_flow', { chatflow_id: 3 }), t, { flows })
      ).toBe('Continua no fluxo “Pós-venda”');
      expect(nodeSummary(node('goto_flow'), t, { flows })).toBe(
        'Escolha o fluxo de destino'
      );
    });

    it('lista, digitando e condição', () => {
      const lists = [{ id: 1, name: 'VIP' }];
      expect(
        nodeSummary(node('list_action', { action: 'remove', list_id: 1 }), t, {
          lists,
        })
      ).toBe('Remove da lista VIP');
      expect(nodeSummary(node('typing', { seconds: 4 }), t)).toBe(
        'Digitando por 4s'
      );
      expect(nodeSummary(node('condition', { rules: [{}, {}] }), t)).toBe(
        'Regras: 2'
      );
    });
  });

  it('A/B: total e próximo ramo livre', () => {
    expect(splitTotal([{ percent: 60 }, { percent: '30' }])).toBe(90);
    expect(nextBranchValue([{ value: 'a' }, { value: 'b' }])).toBe('c');
  });
});
