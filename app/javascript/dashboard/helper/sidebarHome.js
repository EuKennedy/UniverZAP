import { useSidebarLayout } from 'dashboard/composables/useSidebarLayout';

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
export const sidebarHomeRoute = (router, accountId) => {
  const { layout } = useSidebarLayout();
  const home = layout.value?.home;
  if (!home?.route || !accountId) return null;
  // Asked rather than resolved: resolving an unknown name makes vue-router
  // complain in the console of every person signing in.
  if (!router?.hasRoute?.(home.route)) return null;

  return { name: home.route, params: { accountId, ...(home.params || {}) } };
};

export default sidebarHomeRoute;
