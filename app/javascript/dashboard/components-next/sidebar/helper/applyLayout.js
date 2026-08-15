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
 *   - An item that exists and is NOT in the layout still renders. A tab we ship
 *     and forget to position appears at the end, instead of vanishing with no
 *     error, no log and nobody to notice.
 *   - An item in the layout that does not exist for this user is skipped in
 *     silence. An agent without reports permission sees no hole in the menu.
 *   - A layout we cannot parse falls back to the untouched menu. A corrupt
 *     preference must never take the product off the air.
 *
 * ## Why a group is a SECTION and not a parent
 *
 * Version 1 turned a group into another SidebarGroup and put the items inside
 * it as children. That capped what could be grouped at leaves only, because
 * SidebarGroup renders three levels — itself, SidebarSubGroup, SidebarGroupLeaf
 * — and a native group already spends all three: Conversas holds Canais, and
 * Canais holds the inboxes. Wrapping one pushed the inboxes to a fourth level
 * nothing draws, so they disappeared. The guard that followed kept the menu
 * alive by refusing to group exactly the tabs anybody would want to group.
 *
 * A section is a WRAPPER, not a parent: it renders a header and then a
 * SidebarGroup per item, so every item starts its own three levels from
 * scratch. Conversas inside a section is still Conversas, inboxes and all.
 * There is no depth budget to run out of, so there is nothing to refuse.
 */

const VERSION = 2;

/**
 * Version 1, rewritten as version 2 rather than discarded.
 *
 * The old shape carried the same intention in a different arrangement: group
 * membership lived on each item as `group`, and order was a number per item.
 * Dropping it would silently wipe groups a super admin typed by hand, so it is
 * converted instead — and it lands looking exactly like it rendered before,
 * loose items first and groups after, which is the order version 1 forced.
 */
function fromVersion1(layout) {
  if (!Array.isArray(layout.groups)) return null;
  if (!layout.items || typeof layout.items !== 'object') return null;

  const rules = layout.items;
  const at = name => rules[name]?.order ?? 0;
  const byRule = (a, b) => at(a) - at(b);

  const groups = layout.groups
    .slice()
    .sort((a, b) => a.order - b.order)
    .map(group => ({
      id: group.id,
      label: group.label,
      icon: group.icon || null,
      items: Object.keys(rules)
        .filter(name => rules[name]?.group === group.id)
        .sort(byRule),
    }));

  const adopted = new Set(groups.flatMap(group => group.items));
  const loose = Object.keys(rules)
    .filter(name => !adopted.has(name))
    .sort(byRule);

  return {
    version: VERSION,
    order: [...loose, ...groups.map(group => group.id)],
    groups,
    items: rules,
  };
}

/**
 * A layout we can act on, in today's shape, or null when there is none.
 *
 * Exported as `readLayout` because the organiser screen has to read the saved
 * layout too, and a second parser would be a second opinion about the same
 * JSON — the version the sidebar renders and the version the screen shows you
 * would drift apart, silently, the first time either one changed.
 */
function normalise(layout) {
  if (!layout || typeof layout !== 'object') return null;
  if (layout.version === 1) {
    const upgraded = fromVersion1(layout);
    return upgraded && normalise(upgraded);
  }
  if (layout.version !== VERSION) return null;
  if (!Array.isArray(layout.groups)) return null;
  if (!layout.items || typeof layout.items !== 'object') return null;

  return {
    order: Array.isArray(layout.order) ? layout.order : [],
    groups: layout.groups
      .filter(group => group && group.id)
      .map(group => ({
        ...group,
        items: Array.isArray(group.items) ? group.items : [],
      })),
    items: layout.items,
    home: layout.home || null,
  };
}

export { normalise as readLayout, VERSION as LAYOUT_VERSION };

/**
 * @param {Array} menu    the menu as the app built it, top-level entries
 * @param {Object} layout the saved overlay, or null/undefined for none
 * @returns {Array} the entries to render: menu entries, and sections carrying
 *                  their own items under `section: true`
 */
export function applyLayout(menu, layout) {
  if (!Array.isArray(menu)) return [];

  const plan = normalise(layout);
  if (!plan) return menu;

  const rules = plan.items;
  // A hand-written label replaces the translation. Accepted consequence, stated
  // in the design: someone using the panel in English reads it in whatever
  // language the super admin typed.
  const decorate = entry =>
    rules[entry.name]?.label
      ? { ...entry, label: rules[entry.name].label }
      : entry;

  const available = new Map();
  menu.forEach(entry => {
    if (!rules[entry.name]?.hidden) available.set(entry.name, entry);
  });

  // Claimed before anything is placed, so an item listed both inside a section
  // and at the top level renders once — in the section — instead of twice.
  const claimed = new Set();
  const sections = new Map();
  plan.groups.forEach(group => {
    const items = group.items
      .map(name => available.get(name))
      .filter(Boolean)
      .filter(entry => !claimed.has(entry.name));
    items.forEach(entry => claimed.add(entry.name));
    sections.set(group.id, {
      section: true,
      name: group.id,
      label: group.label,
      icon: group.icon || null,
      items: items.map(decorate),
    });
  });

  // An empty section is a click that leads nowhere: every item in it may be
  // hidden, or simply not exist for the person looking.
  const rendered = section => section.items.length > 0;

  const placed = [];
  const seen = new Set();
  plan.order.forEach(name => {
    if (seen.has(name)) return;
    seen.add(name);

    const section = sections.get(name);
    if (section) {
      if (rendered(section)) placed.push(section);
      return;
    }
    const entry = available.get(name);
    if (entry && !claimed.has(name)) placed.push(decorate(entry));
  });

  // A section the order forgot still renders, and so does a tab we shipped and
  // never positioned. Both land at the end, where "new and unplaced" belongs:
  // the super admin sees them in the organiser and puts them where they go.
  sections.forEach((section, id) => {
    if (!seen.has(id) && rendered(section)) placed.push(section);
  });
  menu.forEach(entry => {
    if (seen.has(entry.name) || claimed.has(entry.name)) return;
    if (available.has(entry.name)) placed.push(decorate(entry));
  });

  return placed;
}

export default applyLayout;
