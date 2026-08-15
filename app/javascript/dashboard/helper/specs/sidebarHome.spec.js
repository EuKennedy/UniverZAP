import { sidebarHomeRoute } from '../sidebarHome';

let saved = {};

vi.mock('dashboard/composables/useSidebarLayout', () => ({
  useSidebarLayout: () => ({ layout: { value: saved } }),
}));

// Enough of vue-router to answer the one question this helper asks it.
const router = {
  hasRoute: name => ['kanban_overview', 'portals_index'].includes(name),
};

describe('sidebarHomeRoute', () => {
  beforeEach(() => {
    saved = {};
  });

  it('sends the person to the screen the installation chose', () => {
    saved = { home: { item: 'Kanban', route: 'kanban_overview', params: {} } };

    expect(sidebarHomeRoute(router, 7)).toEqual({
      name: 'kanban_overview',
      params: { accountId: 7 },
    });
  });

  // One global setting is read by people in different accounts, so the account
  // is whoever is looking and never whoever saved it.
  it('resolves against the account of the person arriving', () => {
    saved = { home: { item: 'Kanban', route: 'kanban_overview', params: {} } };

    expect(sidebarHomeRoute(router, 12).params.accountId).toBe(12);
  });

  it('carries the extra params a route needs', () => {
    saved = {
      home: {
        item: 'Portals',
        route: 'portals_index',
        params: { navigationPath: 'portals_articles_index' },
      },
    };

    expect(sidebarHomeRoute(router, 7).params).toEqual({
      accountId: 7,
      navigationPath: 'portals_articles_index',
    });
  });

  // Every one of these has to leave the caller with the product's default
  // landing. A home screen nobody can resolve must never be a locked door.
  describe('falls back rather than keeping anybody out', () => {
    it.each([
      ['nothing was saved', {}],
      ['no home was chosen', { version: 2 }],
      ['the home has no route', { home: { item: 'Kanban' } }],
      ['the route no longer exists', { home: { route: 'renamed_away' } }],
    ])('answers with nothing when %s', (_label, layout) => {
      saved = layout;

      expect(sidebarHomeRoute(router, 7)).toBeNull();
    });

    it('answers with nothing before an account is known', () => {
      saved = { home: { route: 'kanban_overview' } };

      expect(sidebarHomeRoute(router, undefined)).toBeNull();
    });

    it('answers with nothing before there is a router to ask', () => {
      saved = { home: { route: 'kanban_overview' } };

      expect(sidebarHomeRoute(null, 7)).toBeNull();
    });
  });
});
