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

export function useSidebarLayout() {
  const setLayout = next => {
    layout.value = next || {};
  };

  return { layout: readonly(layout), setLayout };
}

export default useSidebarLayout;
