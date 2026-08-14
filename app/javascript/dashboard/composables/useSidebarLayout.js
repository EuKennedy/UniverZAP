import { ref, readonly } from 'vue';

/**
 * The installation's sidebar layout.
 *
 * Seeded from `window.globalConfig`, which ships with the page like every other
 * installation setting — so rendering the sidebar costs no request. Held in a
 * module-level ref rather than read straight from the window so that saving in
 * the organiser updates the real sidebar immediately, instead of after a
 * reload.
 *
 * An empty object means "the menu the product ships with"; applyLayout treats
 * anything it cannot use as exactly that.
 */
const layout = ref(window.globalConfig?.SIDEBAR_LAYOUT || {});

/**
 * The menu as the sidebar built it, published by the sidebar itself.
 *
 * The organiser screen needs the real menu — with this account's inboxes, this
 * user's permissions and the features actually enabled — and that is assembled
 * inside Sidebar.vue. Rebuilding it in the organiser would produce a preview of
 * a menu nobody sees; extracting the builder out of a 962-line component is a
 * refactor for another day. The sidebar is always mounted, so it simply hands
 * over what it built.
 */
const builtMenu = ref([]);

export function useSidebarLayout() {
  const setLayout = next => {
    layout.value = next || {};
  };

  const publishMenu = menu => {
    builtMenu.value = Array.isArray(menu) ? menu : [];
  };

  return {
    layout: readonly(layout),
    setLayout,
    menu: readonly(builtMenu),
    publishMenu,
  };
}

export default useSidebarLayout;
