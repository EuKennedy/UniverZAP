import { sidebarHomeRoute } from '../sidebarHome';

let saved = {};

vi.mock('dashboard/composables/useSidebarLayout', () => ({
  useSidebarLayout: () => ({ layout: { value: saved } }),
}));

// Enough of vue-router to answer the two questions this helper asks it: does
// the route still exist, and what does it demand of whoever opens it.
const META = {
  kanban_overview: {},
  portals_index: {},
  ai_manager: { permissions: ['administrator'] },
};
const router = {
  hasRoute: name => Object.keys(META).includes(name),
  resolve: ({ name }) => ({ meta: META[name] }),
};

const agent = { accounts: [{ id: 7, permissions: ['agent'] }] };
const admin = { accounts: [{ id: 7, permissions: ['administrator'] }] };

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

    // The regression that took production down: the guard sent the agent to a
    // screen only administrators may open, the permission check sent them back
    // to the conversation list — which is the landing that fires this redirect
    // — and the two bounced for ever with the tab pinned at 100% CPU. Answering
    // null here is what breaks the cycle: there is no second leg to bounce off.
    it('answers with nothing when the chosen home is closed to this person', () => {
      saved = { home: { item: 'Gerente', route: 'ai_manager', params: {} } };

      expect(sidebarHomeRoute(router, 7, agent)).toBeNull();
    });

    it('still sends an administrator to that same home', () => {
      saved = { home: { item: 'Gerente', route: 'ai_manager', params: {} } };

      expect(sidebarHomeRoute(router, 7, admin).name).toBe('ai_manager');
    });

    // hasPermissions answers false for an empty requirement, so asking it about
    // an unrestricted route would have shut the feature off for everybody.
    it('does not gate a route that demands nothing', () => {
      saved = {
        home: { item: 'Kanban', route: 'kanban_overview', params: {} },
      };

      expect(sidebarHomeRoute(router, 7, agent).name).toBe('kanban_overview');
    });
  });
});
