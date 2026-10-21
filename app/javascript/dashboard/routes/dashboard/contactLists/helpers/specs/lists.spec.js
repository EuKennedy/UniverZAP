import {
  filterLists,
  memberBadges,
  previewCsv,
  relativeTime,
  summaryCards,
} from '../lists';

const lists = [
  { id: 1, name: 'Clientes VIP', source: 'group', group_name: 'VIP Lourdes' },
  { id: 2, name: 'Promoção Março', source: 'csv', description: 'Escova' },
  { id: 3, name: 'Noivas', source: 'manual' },
];

describe('filterLists', () => {
  it('busca sem acento no nome, na descrição e no grupo', () => {
    expect(filterLists(lists, { query: 'promocao' }).map(l => l.id)).toEqual([
      2,
    ]);
    expect(filterLists(lists, { query: 'lourdes' }).map(l => l.id)).toEqual([
      1,
    ]);
    expect(filterLists(lists, { query: 'escova' }).map(l => l.id)).toEqual([2]);
  });

  it('filtra pela origem', () => {
    expect(filterLists(lists, { source: 'manual' }).map(l => l.id)).toEqual([
      3,
    ]);
    expect(filterLists(lists, {})).toHaveLength(3);
  });
});

describe('memberBadges', () => {
  it('marca quem saiu, novo, sem telefone, frio e admin', () => {
    expect(
      memberBadges({
        status: 'left',
        is_new: false,
        phone: null,
        cold: false,
        role: 'participant',
      })
    ).toEqual(['LEFT', 'NO_PHONE']);
    expect(
      memberBadges({
        status: 'active',
        is_new: true,
        phone: '+5531988881111',
        cold: true,
        role: 'superadmin',
      })
    ).toEqual(['NEW', 'COLD', 'ADMIN']);
  });

  it('membro comum com telefone não tem selo', () => {
    expect(
      memberBadges({ status: 'active', phone: '+5531988881111', role: null })
    ).toEqual([]);
  });
});

describe('summaryCards', () => {
  it('monta os cinco cartões na ordem certa, com zero quando falta', () => {
    const cards = summaryCards({ active: 10, sendable: 6, unconsented: 3 });
    expect(cards.map(card => card.key)).toEqual([
      'ACTIVE',
      'SENDABLE',
      'COLD',
      'NO_PHONE',
      'LEFT',
    ]);
    expect(cards.map(card => card.value)).toEqual([10, 6, 3, 0, 0]);
  });
});

describe('relativeTime', () => {
  const now = new Date('2026-10-21T15:00:00Z').getTime();

  it('fala em horas e dias', () => {
    expect(relativeTime(now / 1000 - 2 * 3600, 'pt-BR', now)).toBe(
      'há 2 horas'
    );
    expect(relativeTime(now / 1000 - 86400, 'pt-BR', now)).toBe('ontem');
  });

  it('vazio sem data', () => {
    expect(relativeTime(null)).toBe('');
  });
});

describe('previewCsv', () => {
  it('mostra as primeiras linhas não vazias', () => {
    expect(previewCsv('a\n\n b \nc\nd\ne\nf', 3)).toEqual(['a', 'b', 'c']);
  });
});
