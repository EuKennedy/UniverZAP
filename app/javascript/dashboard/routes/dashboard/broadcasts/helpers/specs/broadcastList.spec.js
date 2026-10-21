import {
  defaultColumns,
  funnelOf,
  filterBroadcasts,
  pageWindow,
  paginate,
  progressOf,
  replyRateOf,
  usageTone,
  widthClass,
} from '../broadcastList';

const list = [
  { id: 1, name: 'Promoção Escova', status: 'completed' },
  { id: 2, name: 'Aniversariantes de outubro', status: 'draft' },
  { id: 3, name: 'Volta, cliente sumida', status: 'running' },
];

describe('broadcastList helpers', () => {
  it('busca sem acento e filtra por status, mais nova primeiro', () => {
    expect(filterBroadcasts(list).map(i => i.id)).toEqual([3, 2, 1]);
    expect(
      filterBroadcasts(list, { query: 'promocao' }).map(i => i.id)
    ).toEqual([1]);
    expect(filterBroadcasts(list, { status: 'draft' }).map(i => i.id)).toEqual([
      2,
    ]);
  });

  it('pagina e segura a página dentro do total', () => {
    const items = Array.from({ length: 30 }, (_, i) => i);

    expect(paginate(items, 3, 12)).toMatchObject({
      page: 3,
      totalPages: 3,
      start: 24,
      end: 30,
    });
    expect(paginate(items, 9, 12).page).toBe(3);
    expect(paginate([], 1, 12)).toMatchObject({
      page: 1,
      totalPages: 1,
      items: [],
    });
  });

  it('mostra no máximo 7 páginas em volta da atual', () => {
    expect(pageWindow(1, 3)).toEqual([1, 2, 3]);
    expect(pageWindow(10, 20)).toEqual([7, 8, 9, 10, 11, 12, 13]);
    expect(pageWindow(20, 20)).toEqual([14, 15, 16, 17, 18, 19, 20]);
  });

  it('progresso conta enviadas, falhas e puladas; resposta só sobre enviadas', () => {
    const item = {
      recipients_count: 10,
      sent_count: 4,
      failed_count: 1,
      skipped_count: 1,
      replied_count: 1,
    };

    expect(progressOf(item)).toBe(60);
    expect(replyRateOf(item)).toBe(25);
    expect(replyRateOf({ sent_count: 0 })).toBeNull();
    expect(progressOf({ recipients_count: 0 })).toBe(0);
  });

  it('a barra de uso fica âmbar perto do teto e vermelha no teto', () => {
    expect(usageTone(10, 150)).toBe('bg-n-teal-9');
    expect(usageTone(100, 150)).toBe('bg-n-amber-9');
    expect(usageTone(140, 150)).toBe('bg-n-ruby-9');
  });

  it('colunas padrão deixam a data de criação de fora', () => {
    expect(defaultColumns()).not.toContain('created');
    expect(defaultColumns()).toContain('replied');
  });

  it('funil calcula cada etapa sobre as enviadas', () => {
    expect(
      funnelOf({ sent: 10, delivered: 8, read: 5, replied: 2 }).map(s => [
        s.key,
        s.ratio,
      ])
    ).toEqual([
      ['sent', 1],
      ['delivered', 0.8],
      ['read', 0.5],
      ['replied', 0.2],
    ]);
    expect(funnelOf({}).every(s => s.ratio === 0)).toBe(true);
  });

  it('largura da barra em doze avos sem estilo inline', () => {
    expect(widthClass(0)).toBe('w-0');
    expect(widthClass(0.5)).toBe('w-6/12');
    expect(widthClass(1.4)).toBe('w-full');
  });
});
