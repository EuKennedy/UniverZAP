import { funnelByNode, rateTone } from '../funnel';
import { userInputs } from '../simulator';

describe('funil por bloco', () => {
  it('indexa por etapa e calcula quem seguiu (avançou ou concluiu)', () => {
    const map = funnelByNode({
      nodes: [
        {
          node_id: 1,
          entered: 10,
          advanced: 6,
          waiting: 2,
          dropped: 2,
          completed: 0,
        },
        {
          node_id: 2,
          entered: 6,
          advanced: 0,
          waiting: 0,
          dropped: 0,
          completed: 6,
        },
        {
          node_id: 3,
          entered: 0,
          advanced: 0,
          waiting: 0,
          dropped: 0,
          completed: 0,
        },
      ],
    });
    expect(map['1'].rate).toBe(60);
    expect(map['2'].rate).toBe(100);
    expect(map['3'].rate).toBeNull();
  });

  it('cor da taxa', () => {
    expect(rateTone(80)).toBe('text-n-teal-11');
    expect(rateTone(50)).toBe('text-n-amber-11');
    expect(rateTone(10)).toBe('text-n-ruby-11');
    expect(rateTone(null)).toBe('text-n-slate-10');
  });

  it('simulador: só as falas da cliente são reenviadas', () => {
    expect(
      userInputs([
        { type: 'bot', text: 'Oi' },
        { type: 'user', text: 'quero agendar' },
        { type: 'event', event: 'waited' },
      ])
    ).toEqual(['quero agendar']);
  });
});
