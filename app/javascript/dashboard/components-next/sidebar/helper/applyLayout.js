/**
 * Applies the super admin's saved sidebar layout over the menu the app just
 * built.
 *
 * What is saved is NOT the menu — it is the intention about it. The menu still
 * gets built exactly as before, with every permission, plan and feature-flag
 * condition already applied, and this function rearranges that result. The
 * distinction is the whole design: one global layout is read by thousands of
 * people with different permissions, so "an item in the layout that does not
 * exist for you" is the normal case, not an error to patch around.
 *
 * Three properties follow from it, and each one is a bug that would otherwise
 * be invisible:
 *
 *   - An item that exists and is NOT in the layout keeps its place. A tab we
 *     ship and forget to position still appears, instead of vanishing with no
 *     error, no log and nobody to notice.
 *   - An item in the layout that does not exist for this user is skipped in
 *     silence. An agent without reports permission sees no hole in the menu.
 *   - A layout we cannot parse falls back to the untouched menu. A corrupt
 *     preference must never take the product off the air.
 */

/** A layout we can act on: right shape, right version. */
function usable(layout) {
  return (
    layout &&
    typeof layout === 'object' &&
    layout.version === 1 &&
    Array.isArray(layout.groups) &&
    layout.items &&
    typeof layout.items === 'object'
  );
}

/**
 * A native group can be reordered but never adopted into a custom one.
 *
 * The components render three levels — SidebarGroup, SidebarSubGroup,
 * SidebarGroupLeaf — and the native groups already spend all three: Conversas
 * holds Canais, and Canais holds the inboxes. Wrapping one in a custom group
 * pushes its grandchildren to a fourth level, where SidebarGroupLeaf has no way
 * to draw children — so the inboxes vanish, Pastas renders as a dead item and
 * the dropdown arrow never appears.
 *
 * This was removed once, after checking the components and not the data they
 * carry, and it took the live menu apart.
 */
const isNativeGroup = entry =>
  Array.isArray(entry.children) && entry.children.length > 0;

const byOrder = (a, b) => a.order - b.order;

/**
 * @param {Array} menu   the menu as the app built it, top-level entries
 * @param {Object} layout the saved overlay, or null/undefined for none
 * @returns {Array} the entries to render
 */
export function applyLayout(menu, layout) {
  if (!Array.isArray(menu)) return [];
  if (!usable(layout)) return menu;

  const rules = layout.items;
  const decorate = entry => {
    const rule = rules[entry.name];
    // A hand-written label replaces the translation. Accepted consequence,
    // stated in the design: someone using the panel in English reads it in
    // whatever language the super admin typed.
    return rule?.label ? { ...entry, label: rule.label } : entry;
  };

  const visible = menu.filter(entry => !rules[entry.name]?.hidden);

  // Where each entry sits when the layout says nothing about it: exactly where
  // the app put it.
  const fallbackOrder = new Map(
    menu.map((entry, index) => [entry.name, index])
  );
  const positionOf = entry =>
    rules[entry.name]?.order ?? fallbackOrder.get(entry.name) ?? 0;

  const adoptable = new Map();
  const top = [];
  visible.forEach(entry => {
    const target = rules[entry.name]?.group;
    if (target && !isNativeGroup(entry)) {
      const siblings = adoptable.get(target) ?? [];
      siblings.push(entry);
      adoptable.set(target, siblings);
      return;
    }
    top.push(entry);
  });

  const groups = layout.groups
    .slice()
    .sort(byOrder)
    .map(group => ({
      name: group.id,
      label: group.label,
      icon: group.icon,
      children: (adoptable.get(group.id) ?? [])
        .sort((a, b) => positionOf(a) - positionOf(b))
        .map(decorate),
    }))
    // An empty group is a click that leads nowhere — every item in it may be
    // hidden, or simply not exist for the person looking.
    .filter(group => group.children.length > 0);

  const loose = top.sort((a, b) => positionOf(a) - positionOf(b)).map(decorate);

  return [...loose, ...groups];
}

export default applyLayout;
