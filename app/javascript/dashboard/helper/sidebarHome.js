import { useSidebarLayout } from 'dashboard/composables/useSidebarLayout';
import { hasPermissions, getUserPermissions } from './permissionsHelper';

/**
 * The screen the installation opens on.
 *
 * A super admin picks one menu item in the organiser and everybody lands there
 * when they enter the product, instead of on the conversation list it ships
 * with. For an installation sold to salons that live in the agenda, or to a
 * team that lives in the Kanban, the factory landing is a screen they leave
 * again every single morning.
 *
 * What is saved is the ROUTE NAME, not a path: paths carry an account id, and
 * one global setting is read by people in different accounts. The id is put
 * back here, from whoever is looking.
 *
 * Everything about this is best-effort by design. A route we renamed, a layout
 * saved by an older version, a name the router has never heard of — none of
 * them may keep somebody out of the product, so every failure answers with null
 * and the caller falls back to the default landing.
 */
export const sidebarHomeRoute = (router, accountId, user) => {
  const { layout } = useSidebarLayout();
  const home = layout.value?.home;
  if (!home?.route || !accountId) return null;
  // Asked rather than resolved: resolving an unknown name makes vue-router
  // complain in the console of every person signing in.
  if (!router?.hasRoute?.(home.route)) return null;

  const target = {
    name: home.route,
    params: { accountId, ...(home.params || {}) },
  };

  // A home the person cannot open is the one failure that DOES keep them out,
  // and it kept every agent out of the product. The guard sent them to the
  // chosen screen, the permission check sent them back to the conversation
  // list — which IS the landing that triggers this redirect — and the two
  // pushed each other for ever, because vue-router never confirms a redirected
  // navigation and `from` stays START_LOCATION on every pass. The tab spun at
  // 100% CPU with nothing in the console until the browser killed it: every
  // abort is a NavigationFailure swallowed inside the router, and its own
  // redirect-loop brake is compiled out of production builds.
  //
  // Only a route that DEMANDS something is checked: hasPermissions answers
  // false for an empty requirement, so asking it about an unrestricted route
  // would disable the feature for everyone.
  const required = router.resolve(target)?.meta?.permissions || [];
  if (
    required.length &&
    !hasPermissions(required, getUserPermissions(user, accountId))
  ) {
    return null;
  }

  return target;
};

export default sidebarHomeRoute;
