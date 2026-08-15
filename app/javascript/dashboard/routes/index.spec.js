import { START_LOCATION } from 'vue-router';
import { validateAuthenticateRoutePermission } from './index';
import store from '../store'; // This import will be mocked
import { vi } from 'vitest';

const home = vi.fn(() => null);
vi.mock('../helper/sidebarHome', () => ({
  sidebarHomeRoute: (...args) => home(...args),
}));

// Mock the store module
vi.mock('../store', () => ({
  default: {
    getters: {
      isLoggedIn: false,
      getCurrentUser: {
        account_id: null,
        id: null,
        accounts: [],
      },
      'accounts/getAccount': () => ({}),
    },
    dispatch: vi.fn(() => Promise.resolve()),
  },
}));

describe('#validateAuthenticateRoutePermission', () => {
  let next;

  beforeEach(() => {
    vi.restoreAllMocks();
    next = vi.fn(); // Mock the next function
    home.mockReturnValue(null);
  });

  describe('when user is not logged in', () => {
    it('should redirect to login', () => {
      const to = { name: 'some-protected-route', params: { accountId: 1 } };

      // Mock the store to simulate user not logged in
      store.getters.isLoggedIn = false;

      // Mock window.location.assign
      const mockAssign = vi.fn();
      delete window.location;
      window.location = { assign: mockAssign };

      validateAuthenticateRoutePermission(to, next);

      expect(mockAssign).toHaveBeenCalledWith('/app/login');
    });
  });

  describe('when user is logged in', () => {
    beforeEach(() => {
      // Mock the store's getter for a logged-in user
      store.getters.isLoggedIn = true;
      store.getters.getCurrentUser = {
        account_id: 1,
        id: 1,
        accounts: [
          {
            id: 1,
            role: 'agent',
            permissions: ['agent'],
            status: 'active',
          },
        ],
      };
    });

    describe('when route is not accessible to current user', () => {
      it('should redirect to dashboard', async () => {
        const to = {
          name: 'general_settings_index',
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        };

        await validateAuthenticateRoutePermission(to, next);

        expect(next).toHaveBeenCalledWith('/app/accounts/1/dashboard');
      });
    });

    describe('when route is accessible to current user', () => {
      beforeEach(() => {
        // Adjust store getters to reflect the user has admin permissions
        store.getters.getCurrentUser = {
          account_id: 1,
          id: 1,
          accounts: [
            {
              id: 1,
              role: 'administrator',
              permissions: ['administrator'],
              status: 'active',
            },
          ],
        };
      });

      it('should go to the intended route', async () => {
        const to = {
          name: 'general_settings_index',
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        };

        await validateAuthenticateRoutePermission(to, next);

        expect(next).toHaveBeenCalledWith();
      });
    });

    // The screen a super admin chose for the whole installation. Signing in is
    // a full page load onto the conversation list, so the URL alone cannot tell
    // that landing apart from a click on Conversas: what separates them is that
    // entering the product is the first navigation of the page.
    describe('the home screen the installation chose', () => {
      const kanban = { name: 'kanban_overview', params: { accountId: 1 } };
      // Carries its permissions like the real route does, so what these tests
      // measure is the landing and not the permission matrix.
      const conversations = {
        name: 'home',
        params: { accountId: 1 },
        meta: { permissions: ['agent'] },
      };

      it('takes over the landing when the product is being entered', async () => {
        home.mockReturnValue(kanban);

        await validateAuthenticateRoutePermission(
          conversations,
          next,
          START_LOCATION
        );

        expect(next).toHaveBeenCalledWith(kanban);
      });

      // Otherwise the one tab everybody clicks would be the one tab nobody can
      // reach.
      it('leaves a click on Conversas alone', async () => {
        home.mockReturnValue(kanban);

        await validateAuthenticateRoutePermission(conversations, next, {
          name: 'kanban_overview',
        });

        expect(next).not.toHaveBeenCalledWith(kanban);
      });

      // Refreshing is staying put, not arriving. Otherwise an agent who reloads
      // the list they are reading gets thrown to the home screen, all day.
      it('leaves a refresh where it was', async () => {
        home.mockReturnValue(kanban);
        vi.spyOn(performance, 'getEntriesByType').mockReturnValue([
          { type: 'reload' },
        ]);

        await validateAuthenticateRoutePermission(
          conversations,
          next,
          START_LOCATION
        );

        expect(next).toHaveBeenCalledWith();
      });

      it('leaves the landing alone when nobody chose one', async () => {
        await validateAuthenticateRoutePermission(
          conversations,
          next,
          START_LOCATION
        );

        expect(next).toHaveBeenCalledWith();
      });

      // A home screen pointing at the conversation list is the default said out
      // loud, and redirecting a navigation to itself never finishes.
      it('does not send the conversation list to the conversation list', async () => {
        home.mockReturnValue(conversations);

        await validateAuthenticateRoutePermission(
          conversations,
          next,
          START_LOCATION
        );

        expect(next).toHaveBeenCalledWith();
      });

      // Setting the account up comes first: a home screen is no use to somebody
      // who does not have an account yet.
      it('waits for onboarding to finish', async () => {
        home.mockReturnValue(kanban);
        store.getters.getCurrentUser = {
          account_id: 1,
          id: 1,
          accounts: [
            {
              id: 1,
              role: 'administrator',
              permissions: ['administrator'],
              status: 'active',
              onboarding_step: 'account_details',
            },
          ],
        };

        await validateAuthenticateRoutePermission(
          conversations,
          next,
          START_LOCATION
        );

        expect(next).toHaveBeenCalledWith('/app/accounts/1/onboarding');
      });
    });
  });
});
