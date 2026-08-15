import { createRouter, createWebHistory, START_LOCATION } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import { sidebarHomeRoute } from '../helper/sidebarHome';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const ONBOARDING_STEPS = ['account_details', 'enrichment'];
const routes = [...dashboard.routes];

export const router = createRouter({ history: createWebHistory(), routes });

/**
 * A refresh is somebody staying put, not arriving.
 *
 * Without this, an agent who reloads the conversation list gets thrown to the
 * home screen instead of back to the list they were reading — all day, every
 * time. Unknown counts as a normal arrival, because losing the home screen is
 * a smaller failure than hijacking somebody's reload.
 */
const isReload = () => {
  const entries = window.performance?.getEntriesByType?.('navigation') ?? [];
  return entries[0]?.type === 'reload';
};

/**
 * Somebody arriving at the product, rather than moving around inside it.
 *
 * Signing in is a full page load onto the conversation list, so the URL alone
 * cannot tell that landing apart from a click on Conversas — and the
 * installation's home screen must never hijack a link somebody chose. What
 * separates them is that entering the product is the FIRST navigation of the
 * page: any click has a route behind it, and this one has START_LOCATION.
 *
 * A bare /app URL matches no route and is sent to the conversation list by the
 * branch below, which comes back through here with a name and START_LOCATION
 * still standing, because no navigation has been confirmed yet.
 */
const isEnteringTheProduct = (to, from) =>
  from === START_LOCATION && to.name === 'home' && !isReload();

export const validateAuthenticateRoutePermission = async (to, next, from) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  const routeAccountId = Number(to.params?.accountId || accountId);
  const userAccount = accounts.find(a => a.id === routeAccountId);
  const isAdmin = userAccount?.role === 'administrator';
  const isActive = userAccount?.status === 'active';
  const needsOnboarding =
    ONBOARDING_STEPS.includes(userAccount?.onboarding_step) &&
    isAdmin &&
    isActive;

  if (to.name === 'no_accounts' || !to.name) {
    const target = needsOnboarding ? 'onboarding' : 'dashboard';
    return next(frontendURL(`accounts/${routeAccountId}/${target}`));
  }

  // The screen a super admin chose for the whole installation. Skipped when the
  // home IS the route being visited, which would otherwise redirect a
  // navigation to itself, forever.
  if (!needsOnboarding && isEnteringTheProduct(to, from)) {
    const home = sidebarHomeRoute(router, routeAccountId);
    if (home && home.name !== to.name) return next(home);
  }

  if (needsOnboarding && !isOnOnboardingView(to)) {
    return next(frontendURL(`accounts/${routeAccountId}/onboarding`));
  }
  if (!needsOnboarding && isOnOnboardingView(to)) {
    return next(frontendURL(`accounts/${routeAccountId}/dashboard`));
  }

  const nextRoute = validateLoggedInRoutes(to, store.getters.getCurrentUser);
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  router.beforeEach(async (to, from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    await userAuthentication;
    await validateAuthenticateRoutePermission(to, next, from);
  });
};

export default router;
