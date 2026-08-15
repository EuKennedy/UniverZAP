import { applyLayout } from '../applyLayout';

// The menu as the app builds it: loose leaves plus native groups with children.
const menu = () => [
  { name: 'Inbox', label: 'Caixa de entrada', to: '/inbox' },
  {
    name: 'Conversation',
    label: 'Conversas',
    children: [{ name: 'All', label: 'Todas', to: '/all' }],
  },
  { name: 'Contact', label: 'Contatos', to: '/contacts' },
  { name: 'Report', label: 'Relatórios', to: '/reports' },
];

const layout = overrides => ({
  version: 1,
  groups: [{ id: 'g_gestao', label: 'Gestão', order: 0 }],
  items: {},
  ...overrides,
});

const names = entries => entries.map(e => e.name);

describe('applyLayout', () => {
  describe('when there is nothing usable to apply', () => {
    // A corrupt preference must never take the product off the air: at worst
    // the customer sees the factory menu and a super admin fixes it.
    it.each([
      ['null', null],
      ['undefined', undefined],
      ['a version we do not know', { version: 99, groups: [], items: {} }],
      ['groups that are not a list', { version: 1, groups: 'nope', items: {} }],
      ['no items map', { version: 1, groups: [] }],
    ])('falls back to the untouched menu given %s', (_label, bad) => {
      expect(applyLayout(menu(), bad)).toEqual(menu());
    });

    it('survives a menu that is not a list', () => {
      expect(applyLayout(null, layout())).toEqual([]);
    });
  });

  describe('placing items', () => {
    it('moves an item into the group it was assigned', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { group: 'g_gestao', order: 0 } } })
      );

      expect(names(result)).toEqual([
        'Inbox',
        'Conversation',
        'Contact',
        'g_gestao',
      ]);
      expect(names(result.at(-1).children)).toEqual(['Report']);
    });

    it('orders the items inside a group by what the layout says', () => {
      const result = applyLayout(
        menu(),
        layout({
          items: {
            Report: { group: 'g_gestao', order: 1 },
            Contact: { group: 'g_gestao', order: 0 },
          },
        })
      );

      expect(names(result.at(-1).children)).toEqual(['Contact', 'Report']);
    });

    it('reorders loose items', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Contact: { order: -1 } } })
      );

      expect(names(result)[0]).toBe('Contact');
    });

    // A tab we ship and forget to position must still appear. Vanishing would
    // be silent: no error, no log, and the customer never knows it exists.
    it('keeps an item the layout says nothing about, where it already was', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { group: 'g_gestao', order: 0 } } })
      );

      expect(names(result).slice(0, 3)).toEqual([
        'Inbox',
        'Conversation',
        'Contact',
      ]);
    });

    // The same global layout is read by people with different permissions.
    it('ignores an item that does not exist for this person', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Billing: { group: 'g_gestao', order: 0 } } })
      );

      expect(names(result)).toEqual([
        'Inbox',
        'Conversation',
        'Contact',
        'Report',
      ]);
    });

    // SidebarGroup renders a SidebarSubGroup per child, which renders its own
    // leaves — so custom group → native group → leaves is three levels the
    // sidebar already draws, and a native group can be adopted like anything
    // else.
    it('adopts a native group into a custom one, children and all', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Conversation: { group: 'g_gestao', order: 0 } } })
      );

      const custom = result.find(entry => entry.name === 'g_gestao');
      expect(names(custom.children)).toEqual(['Conversation']);
      expect(names(custom.children[0].children)).toEqual(['All']);
    });
  });

  describe('hiding and renaming', () => {
    it('removes a hidden item', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { hidden: true } } })
      );

      expect(names(result)).not.toContain('Report');
    });

    it('drops a group whose items are all hidden', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { group: 'g_gestao', hidden: true } } })
      );

      // An empty group is a click that leads nowhere.
      expect(names(result)).not.toContain('g_gestao');
    });

    it('replaces the label with the one that was typed', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { label: 'Números' } } })
      );

      expect(result.find(e => e.name === 'Report').label).toBe('Números');
    });

    it('renames an item that lives inside a group', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { group: 'g_gestao', label: 'Números' } } })
      );

      expect(result.at(-1).children[0].label).toBe('Números');
    });

    it('leaves the original menu untouched', () => {
      const original = menu();
      applyLayout(
        original,
        layout({ items: { Report: { label: 'Números' } } })
      );

      expect(original.find(e => e.name === 'Report').label).toBe('Relatórios');
    });
  });

  describe('groups', () => {
    it('renders them in the order the layout gives', () => {
      const result = applyLayout(menu(), {
        version: 1,
        groups: [
          { id: 'g_b', label: 'B', order: 1 },
          { id: 'g_a', label: 'A', order: 0 },
        ],
        items: {
          Report: { group: 'g_b', order: 0 },
          Contact: { group: 'g_a', order: 0 },
        },
      });

      expect(names(result).slice(-2)).toEqual(['g_a', 'g_b']);
    });

    it('drops a group nobody was put into', () => {
      expect(names(applyLayout(menu(), layout()))).not.toContain('g_gestao');
    });
  });
});
