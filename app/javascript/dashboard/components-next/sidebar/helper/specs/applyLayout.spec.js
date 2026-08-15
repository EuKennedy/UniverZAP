import { applyLayout } from '../applyLayout';

// The menu as the app builds it: plain entries plus native groups that carry
// children of their own.
const menu = () => [
  { name: 'Inbox', label: 'Caixa de entrada', to: '/inbox' },
  {
    name: 'Conversation',
    label: 'Conversas',
    children: [
      { name: 'All', label: 'Todas', to: '/all' },
      {
        name: 'Channels',
        label: 'Canais',
        children: [{ name: 'WhatsApp-1', label: 'WhatsApp', to: '/inbox/1' }],
      },
    ],
  },
  { name: 'Kanban', label: 'Kanban', to: '/kanban' },
  { name: 'Report', label: 'Relatórios', to: '/reports' },
];

const layout = overrides => ({
  version: 2,
  order: [],
  groups: [],
  items: {},
  ...overrides,
});

const names = entries => entries.map(entry => entry.name);
const find = (entries, name) => entries.find(entry => entry.name === name);

describe('applyLayout', () => {
  describe('when there is nothing usable to apply', () => {
    // A corrupt preference must never take the product off the air: at worst
    // the customer sees the factory menu and a super admin fixes it.
    it.each([
      ['null', null],
      ['undefined', undefined],
      ['a version we do not know', { version: 99, groups: [], items: {} }],
      ['groups that are not a list', { version: 2, groups: 'nope', items: {} }],
      ['no items map', { version: 2, groups: [] }],
    ])('falls back to the untouched menu given %s', (_label, bad) => {
      expect(applyLayout(menu(), bad)).toEqual(menu());
    });

    it('survives a menu that is not a list', () => {
      expect(applyLayout(null, layout())).toEqual([]);
    });
  });

  describe('sections', () => {
    const withSection = items =>
      layout({
        order: ['Inbox', 'g_gestao'],
        groups: [{ id: 'g_gestao', label: 'Gestão', icon: 'i-x', items }],
      });

    it('puts the items it was given inside the section', () => {
      const result = applyLayout(menu(), withSection(['Report']));

      const section = find(result, 'g_gestao');
      expect(section.section).toBe(true);
      expect(section.label).toBe('Gestão');
      expect(names(section.items)).toEqual(['Report']);
    });

    // The whole reason this was rebuilt. Version 1 turned a group into another
    // SidebarGroup, which cost a render level the native groups had already
    // spent, so the inboxes fell off the end and the guard that followed simply
    // refused to group them at all. A section wraps instead of parenting, so
    // there is no level to lose and nothing to refuse.
    it('takes a native group in whole, grandchildren and all', () => {
      const result = applyLayout(menu(), withSection(['Conversation']));

      const conversation = find(result, 'g_gestao').items[0];
      expect(conversation.name).toBe('Conversation');
      expect(names(conversation.children)).toEqual(['All', 'Channels']);
      expect(names(conversation.children[1].children)).toEqual(['WhatsApp-1']);
    });

    it('keeps the order the items were given inside it', () => {
      const result = applyLayout(menu(), withSection(['Report', 'Kanban']));

      expect(names(find(result, 'g_gestao').items)).toEqual([
        'Report',
        'Kanban',
      ]);
    });

    // A section is a slot in the same list as the items, which is what makes
    // "group, then a loose tab, then another group" expressible at all.
    it('sits wherever the order puts it', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['g_gestao', 'Inbox'],
          groups: [{ id: 'g_gestao', label: 'Gestão', items: ['Report'] }],
        })
      );

      expect(names(result).slice(0, 2)).toEqual(['g_gestao', 'Inbox']);
    });

    // An empty one is a heading that opens onto nothing: every item in it may
    // be hidden, or simply not exist for the person looking.
    it('drops a section nobody was put into', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['g_gestao'],
          groups: [{ id: 'g_gestao', label: 'Gestão', items: [] }],
        })
      );

      expect(names(result)).not.toContain('g_gestao');
    });

    it('drops a section whose items are all hidden', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['g_gestao'],
          groups: [{ id: 'g_gestao', label: 'Gestão', items: ['Report'] }],
          items: { Report: { hidden: true } },
        })
      );

      expect(names(result)).not.toContain('g_gestao');
    });

    // Two sections claiming the same tab is a layout we could write ourselves
    // by mistake. Rendering it twice would give the customer two tabs that
    // fight over which one looks active.
    it('renders an item claimed by two sections exactly once', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['g_a', 'g_b'],
          groups: [
            { id: 'g_a', label: 'A', items: ['Report'] },
            { id: 'g_b', label: 'B', items: ['Report'] },
          ],
        })
      );

      expect(names(find(result, 'g_a').items)).toEqual(['Report']);
      expect(names(result)).not.toContain('g_b');
    });

    it('never renders an item both loose and inside a section', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['Report', 'g_gestao'],
          groups: [{ id: 'g_gestao', label: 'Gestão', items: ['Report'] }],
        })
      );

      expect(names(result).filter(name => name === 'Report')).toHaveLength(0);
      expect(names(find(result, 'g_gestao').items)).toEqual(['Report']);
    });
  });

  describe('what the layout does not mention', () => {
    // A tab we ship and forget to position must still appear. Vanishing would
    // be silent: no error, no log, and the customer never knows it exists.
    it('still renders a tab nobody positioned, at the end', () => {
      const result = applyLayout(menu(), layout({ order: ['Report'] }));

      expect(names(result)).toEqual([
        'Report',
        'Inbox',
        'Conversation',
        'Kanban',
      ]);
    });

    it('still renders a section the order forgot', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: [],
          groups: [{ id: 'g_gestao', label: 'Gestão', items: ['Report'] }],
        })
      );

      expect(names(result)).toContain('g_gestao');
    });

    // The same global layout is read by people with different permissions, so
    // an item that is not in this person's menu is normal, not an error.
    it('ignores an item that does not exist for this person', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['Billing', 'g_gestao'],
          groups: [
            { id: 'g_gestao', label: 'Gestão', items: ['Billing', 'Report'] },
          ],
        })
      );

      expect(names(result)).not.toContain('Billing');
      expect(names(find(result, 'g_gestao').items)).toEqual(['Report']);
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

    it('replaces the label with the one that was typed', () => {
      const result = applyLayout(
        menu(),
        layout({ items: { Report: { label: 'Números' } } })
      );

      expect(find(result, 'Report').label).toBe('Números');
    });

    it('renames an item that lives inside a section', () => {
      const result = applyLayout(
        menu(),
        layout({
          order: ['g_gestao'],
          groups: [{ id: 'g_gestao', label: 'Gestão', items: ['Report'] }],
          items: { Report: { label: 'Números' } },
        })
      );

      expect(find(result, 'g_gestao').items[0].label).toBe('Números');
    });

    it('leaves the original menu untouched', () => {
      const original = menu();
      applyLayout(
        original,
        layout({ items: { Report: { label: 'Números' } } })
      );

      expect(find(original, 'Report').label).toBe('Relatórios');
    });
  });

  // Groups a super admin typed by hand must survive the rebuild. Discarding
  // them would look exactly like the product forgetting their work.
  describe('a layout saved by the previous version', () => {
    const version1 = {
      version: 1,
      groups: [
        { id: 'g_gestao', label: 'Gestão', order: 1 },
        { id: 'g_atendimento', label: 'Atendimento', order: 0 },
      ],
      items: {
        Inbox: { order: 0 },
        Report: { group: 'g_gestao', order: 0 },
        Kanban: { group: 'g_atendimento', order: 0, label: 'Funis' },
      },
    };

    it('reads as sections, in the order it used to render', () => {
      const result = applyLayout(menu(), version1);

      // Version 1 always drew every loose item before every group.
      expect(names(result)).toEqual([
        'Inbox',
        'g_atendimento',
        'g_gestao',
        'Conversation',
      ]);
    });

    it('keeps the members and the names that were typed', () => {
      const result = applyLayout(menu(), version1);

      expect(names(find(result, 'g_gestao').items)).toEqual(['Report']);
      expect(find(result, 'g_atendimento').items[0].label).toBe('Funis');
    });
  });
});
