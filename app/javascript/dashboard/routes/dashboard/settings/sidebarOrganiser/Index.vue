<script setup>
/**
 * Where a super admin builds the sidebar every tenant sees.
 *
 * One ordered list holds everything: a menu item and a group are both slots in
 * it, so a group can sit between two items and an item can be dragged into a
 * group and back out. The first version kept two lists — loose items and groups
 * — which made the order between them impossible to express, and it only ever
 * offered the leaves, so the tabs anybody actually wants to file away
 * (Conversas, Contatos, Relatórios) never appeared on this screen at all.
 */
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useSidebarLayout } from 'dashboard/composables/useSidebarLayout';
import {
  applyLayout,
  readLayout,
  LAYOUT_VERSION,
  pageId,
} from 'dashboard/components-next/sidebar/helper/applyLayout';
import SidebarLayoutAPI from 'dashboard/api/sidebarLayout';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OrganiserItemRow from './OrganiserItemRow.vue';

const { t } = useI18n();
// The menu comes from the sidebar itself, so the preview runs on exactly what
// the real sidebar renders instead of a rebuilt guess.
const { layout: savedLayout, setLayout, menu } = useSidebarLayout();

const entries = ref([]);
const homeItem = ref('');
const sidebarMode = ref('rail');
const isSaving = ref(false);
const pickingIconFor = ref('');

// Enough to say what a section is about without turning this into an icon
// browser. A section nobody gave an icon renders without one, which is a
// legitimate look, not a hole.
const GROUP_ICONS = [
  'i-lucide-folder',
  'i-lucide-headset',
  'i-lucide-trending-up',
  'i-lucide-briefcase',
  'i-lucide-users',
  'i-lucide-bot',
  'i-lucide-chart-spline',
  'i-lucide-megaphone',
  'i-lucide-sparkles',
  'i-lucide-shopping-bag',
  'i-lucide-bolt',
  'i-lucide-life-buoy',
];

// Generated, never borrowed from an item's `name`, so deleting a group can
// never take an item down with it.
const MODES = ['rail', 'classic'];

const newGroupId = () => `g_${Date.now()}_${Math.floor(Math.random() * 1e4)}`;

// The route a menu entry lands on. A native group has none of its own — it is a
// heading — so the first child that goes somewhere is what "open on Conversas"
// has to mean. The account id is stripped: one global setting is read by people
// in different accounts, and it is put back at redirect time.
const destinationOf = entry => {
  const own = entry.to?.name ? entry.to : null;
  const child = (entry.children || [])
    .flatMap(item => (item.children?.length ? item.children : [item]))
    .find(item => item.to?.name);
  const to = own || child?.to;
  if (!to?.name) return { route: '', routeParams: {} };

  const routeParams = { ...(to.params || {}) };
  delete routeParams.accountId;
  return { route: to.name, routeParams };
};

// The pages each entry holds in this layout, in order. Same rule as the
// sidebar: a page nobody listed stays at the end of the entry that ships it.
const placePages = plan => {
  const parents = (menu.value || []).filter(entry =>
    Array.isArray(entry.children)
  );
  const catalog = new Map();
  parents.forEach(entry =>
    entry.children.forEach(child => {
      const id = pageId(entry.name, child.name);
      catalog.set(id, {
        id,
        original: child.label,
        label: plan.pageRules?.[id]?.label || '',
        hidden: Boolean(plan.pageRules?.[id]?.hidden),
      });
    })
  );

  const taken = new Set();
  const placed = new Map();
  parents.forEach(entry => {
    const ids = (plan.pages?.[entry.name] || []).filter(
      id => catalog.has(id) && !taken.has(id)
    );
    ids.forEach(id => taken.add(id));
    placed.set(entry.name, ids);
  });

  return new Map(
    parents.map(entry => {
      const rest = entry.children
        .map(child => pageId(entry.name, child.name))
        .filter(id => !taken.has(id));
      const ids = [...placed.get(entry.name), ...rest];
      return [entry.name, ids.map(id => catalog.get(id))];
    })
  );
};

const hydrate = () => {
  const plan = readLayout(savedLayout.value) || {
    order: [],
    groups: [],
    items: {},
    home: null,
  };
  const rules = plan.items;

  const pages = placePages(plan);
  const catalog = new Map();
  (menu.value || []).forEach(entry => {
    catalog.set(entry.name, {
      kind: 'item',
      name: entry.name,
      icon: entry.icon,
      original: entry.label,
      label: rules[entry.name]?.label || '',
      railLabel: rules[entry.name]?.railLabel || '',
      hidden: Boolean(rules[entry.name]?.hidden),
      pages: pages.get(entry.name),
      // Shown as a badge: this row is a tab that brings its own sub-tabs, and
      // filing it away files all of them.
      childCount: entry.children?.length || 0,
      ...destinationOf(entry),
    });
  });

  const taken = new Set();
  const groups = new Map();
  plan.groups.forEach(group => {
    const items = group.items
      .map(name => catalog.get(name))
      .filter(Boolean)
      .filter(item => !taken.has(item.name));
    items.forEach(item => taken.add(item.name));
    groups.set(group.id, {
      kind: 'group',
      id: group.id,
      label: group.label,
      icon: group.icon || '',
      items,
    });
  });

  const placed = [];
  const seen = new Set();
  plan.order.forEach(name => {
    if (seen.has(name)) return;
    seen.add(name);

    const group = groups.get(name);
    if (group) {
      placed.push(group);
      return;
    }
    const item = catalog.get(name);
    if (item && !taken.has(name)) placed.push(item);
  });

  // A group the order forgot, and a tab we shipped after this layout was saved,
  // both belong at the end rather than nowhere.
  groups.forEach((group, id) => {
    if (!seen.has(id)) placed.push(group);
  });
  catalog.forEach(item => {
    if (!seen.has(item.name) && !taken.has(item.name)) placed.push(item);
  });

  entries.value = placed;
  homeItem.value = plan.home?.item || '';
  sidebarMode.value = plan.sidebarMode || 'rail';
};

// The sidebar publishes its menu a tick after this mounts, so build from it
// whenever it arrives.
watch(menu, hydrate, { immediate: true });

const allItems = computed(() =>
  entries.value.flatMap(entry =>
    entry.kind === 'group' ? entry.items : [entry]
  )
);

const homeTarget = computed(() => {
  const chosen = allItems.value.find(item => item.name === homeItem.value);
  if (!chosen?.route) return null;

  return { item: chosen.name, route: chosen.route, params: chosen.routeParams };
});

const draft = computed(() => {
  // Same restraint as the items below: only an entry whose pages differ from what the
  // product ships gets a list, so a page we add later still shows up there.
  const pages = {};
  const pageRules = {};
  const recordPages = item => {
    if (!item.pages) return;
    const ids = item.pages.map(page => page.id);
    const shipped = menu.value
      .find(entry => entry.name === item.name)
      .children.map(child => pageId(item.name, child.name));
    if (ids.join() !== shipped.join()) pages[item.name] = ids;
    item.pages.forEach(page => {
      const rule = {};
      if (page.hidden) rule.hidden = true;
      if (page.label) rule.label = page.label;
      if (Object.keys(rule).length) pageRules[page.id] = rule;
    });
  };

  const items = {};
  // Only what was actually changed is written down. A map with a row per menu
  // item would grow a permanent entry for every tab we ever ship, and the
  // difference between "positioned here" and "never touched" would be lost.
  const record = item => {
    const rule = {};
    if (item.hidden) rule.hidden = true;
    if (item.label) rule.label = item.label;
    if (item.railLabel) rule.railLabel = item.railLabel;
    if (Object.keys(rule).length) items[item.name] = rule;
    recordPages(item);
  };

  const order = [];
  const groups = [];
  entries.value.forEach(entry => {
    if (entry.kind === 'group') {
      order.push(entry.id);
      groups.push({
        id: entry.id,
        label: entry.label,
        icon: entry.icon || null,
        items: entry.items.map(item => item.name),
      });
      entry.items.forEach(record);
      return;
    }
    order.push(entry.name);
    record(entry);
  });

  const layout = {
    version: LAYOUT_VERSION,
    order,
    groups,
    items,
  };
  if (Object.keys(pages).length) layout.pages = pages;
  if (Object.keys(pageRules).length) layout.pageRules = pageRules;
  if (sidebarMode.value !== 'rail') layout.sidebarMode = sidebarMode.value;
  if (homeTarget.value) layout.home = homeTarget.value;
  return layout;
});

// The same function the sidebar runs. Anything else would preview a menu nobody
// will ever see.
const preview = computed(() => applyLayout(menu.value, draft.value));

// A group inside a group is a level the sidebar does not render, so the nested
// lists take items only.
const acceptsItemsOnly = (_to, _from, dragged) =>
  dragged.dataset.kind === 'item';

const addGroup = () => {
  entries.value.push({
    kind: 'group',
    id: newGroupId(),
    label: t('SIDEBAR_ORGANISER.NEW_GROUP'),
    icon: 'i-lucide-folder',
    items: [],
  });
};

const removeGroup = id => {
  const at = entries.value.findIndex(entry => entry.id === id);
  if (at === -1) return;

  // The items stay where the group was, rather than going down with it or
  // being exiled to the bottom of a list the super admin just organised.
  const released = entries.value[at].items;
  entries.value.splice(at, 1, ...released);
};

const toggleIconPicker = id => {
  pickingIconFor.value = pickingIconFor.value === id ? '' : id;
};

const chooseIcon = (group, icon) => {
  group.icon = group.icon === icon ? '' : icon;
  pickingIconFor.value = '';
};

// Only one screen can be the one that opens, so this is a choice and not a
// checkbox: picking a second clears the first, and picking the current one
// again goes back to the product's default landing.
const toggleHome = item => {
  homeItem.value = homeItem.value === item.name ? '' : item.name;
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await SidebarLayoutAPI.update(draft.value);
    setLayout(data.layout);
    useAlert(t('SIDEBAR_ORGANISER.SAVED'));
  } catch (error) {
    useAlert(t('SIDEBAR_ORGANISER.SAVE_FAILED'));
  } finally {
    isSaving.value = false;
  }
};

const resetAll = () => {
  homeItem.value = '';
  sidebarMode.value = 'rail';
  const shippedPages = placePages({});
  entries.value = allItems.value.map(item => ({
    ...item,
    hidden: false,
    label: '',
    railLabel: '',
    pages: shippedPages.get(item.name),
  }));
  // Back to the order the product ships with, not to the order this screen
  // happened to be showing.
  const shipped = (menu.value || []).map(entry => entry.name);
  entries.value.sort(
    (a, b) => shipped.indexOf(a.name) - shipped.indexOf(b.name)
  );
};
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <header class="flex gap-4 justify-between items-start">
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('SIDEBAR_ORGANISER.TITLE') }}
        </h1>
        <p class="m-0 max-w-2xl text-sm text-n-slate-11">
          {{ t('SIDEBAR_ORGANISER.SUBTITLE') }}
        </p>
      </div>
      <div class="flex flex-shrink-0 gap-2 items-center">
        <Button
          size="sm"
          variant="ghost"
          :label="t('SIDEBAR_ORGANISER.RESET')"
          @click="resetAll"
        />
        <Button
          size="sm"
          :label="t('SIDEBAR_ORGANISER.SAVE')"
          :is-loading="isSaving"
          @click="save"
        />
      </div>
    </header>

    <section class="flex flex-col gap-2 p-3 rounded-xl border border-n-weak">
      <h2 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('SIDEBAR_ORGANISER.MODE') }}
      </h2>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <button
          v-for="mode in MODES"
          :key="mode"
          type="button"
          class="flex flex-col gap-0.5 p-2.5 text-start rounded-lg border transition-colors"
          :class="
            sidebarMode === mode
              ? 'border-n-teal-7 bg-brand-gradient-soft'
              : 'border-n-weak hover:bg-n-alpha-1'
          "
          :aria-pressed="sidebarMode === mode"
          @click="sidebarMode = mode"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`SIDEBAR_ORGANISER.MODE_${mode.toUpperCase()}`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t(`SIDEBAR_ORGANISER.MODE_${mode.toUpperCase()}_HINT`) }}
          </span>
        </button>
      </div>
      <p class="m-0 text-xs text-n-slate-10">
        {{ t('SIDEBAR_ORGANISER.MODE_HINT') }}
      </p>
    </section>

    <div class="grid grid-cols-1 xl:grid-cols-[1fr_18rem] gap-6 items-start">
      <section class="flex flex-col gap-3">
        <div class="flex gap-4 justify-between items-start">
          <div class="flex flex-col gap-1">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('SIDEBAR_ORGANISER.ITEMS') }}
            </h2>
            <p class="m-0 max-w-xl text-[13px] text-n-slate-11">
              {{ t('SIDEBAR_ORGANISER.ITEMS_HINT') }}
            </p>
          </div>
          <Button
            size="sm"
            variant="ghost"
            icon="i-lucide-plus"
            class="flex-shrink-0"
            :label="t('SIDEBAR_ORGANISER.ADD_GROUP')"
            @click="addGroup"
          />
        </div>

        <Draggable
          v-model="entries"
          :group="{ name: 'menu' }"
          :item-key="entry => entry.id || entry.name"
          handle=".drag-handle"
          tag="ul"
          class="flex flex-col gap-1.5 p-2 rounded-xl border border-dashed min-h-16 border-n-weak"
        >
          <template #item="{ element: entry }">
            <li :data-kind="entry.kind" class="list-none">
              <!-- A group: a heading with its own list inside. -->
              <div
                v-if="entry.kind === 'group'"
                class="flex flex-col gap-2 p-2.5 rounded-lg border border-n-weak bg-n-solid-1"
              >
                <div class="flex gap-2 items-center">
                  <Icon
                    icon="i-lucide-grip-vertical"
                    class="flex-shrink-0 cursor-grab drag-handle size-4 text-n-slate-10"
                  />
                  <div class="relative flex-shrink-0">
                    <button
                      type="button"
                      class="grid rounded place-content-center size-7 text-n-slate-11 hover:bg-n-alpha-1"
                      :title="t('SIDEBAR_ORGANISER.ICON')"
                      @click="toggleIconPicker(entry.id)"
                    >
                      <Icon
                        :icon="entry.icon || 'i-lucide-image-plus'"
                        class="size-4"
                      />
                    </button>
                    <div
                      v-if="pickingIconFor === entry.id"
                      class="grid absolute z-20 grid-cols-6 gap-1 p-2 rounded-lg border shadow-lg top-8 ltr:left-0 rtl:right-0 w-52 border-n-weak bg-n-solid-1"
                    >
                      <button
                        v-for="icon in GROUP_ICONS"
                        :key="icon"
                        type="button"
                        class="grid rounded place-content-center size-7 hover:bg-n-alpha-2"
                        :class="
                          entry.icon === icon
                            ? 'text-n-slate-12 bg-n-alpha-2'
                            : 'text-n-slate-11'
                        "
                        @click="chooseIcon(entry, icon)"
                      >
                        <Icon :icon="icon" class="size-4" />
                      </button>
                    </div>
                  </div>
                  <input
                    v-model="entry.label"
                    :placeholder="t('SIDEBAR_ORGANISER.GROUP_NAME')"
                    class="flex-1 px-2 h-8 min-w-0 text-sm font-medium bg-transparent rounded outline-none text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
                  />
                  <Button
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    :title="t('SIDEBAR_ORGANISER.REMOVE_GROUP')"
                    @click="removeGroup(entry.id)"
                  />
                </div>

                <Draggable
                  v-model="entry.items"
                  :group="{ name: 'menu', put: acceptsItemsOnly }"
                  :item-key="item => item.name"
                  handle=".drag-handle"
                  tag="ul"
                  class="flex flex-col gap-1 p-1.5 rounded-md border border-dashed min-h-11 border-n-weak"
                >
                  <template #item="{ element: item }">
                    <li data-kind="item" class="list-none">
                      <OrganiserItemRow
                        :item="item"
                        :is-home="homeItem === item.name"
                        @toggle-home="toggleHome"
                      />
                    </li>
                  </template>
                </Draggable>

                <p
                  v-if="!entry.items.length"
                  class="m-0 text-[12px] text-n-slate-10"
                >
                  {{ t('SIDEBAR_ORGANISER.DROP_HERE') }}
                </p>
              </div>

              <!-- A menu item, sitting on its own. -->
              <OrganiserItemRow
                v-else
                :item="entry"
                :is-home="homeItem === entry.name"
                @toggle-home="toggleHome"
              />
            </li>
          </template>
        </Draggable>

        <p class="m-0 text-[13px] text-n-slate-11">
          {{ t('SIDEBAR_ORGANISER.HOME_HINT') }}
        </p>
      </section>

      <aside
        class="flex sticky top-6 flex-col gap-1 p-3 rounded-xl border border-n-weak bg-n-solid-1"
      >
        <h2 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('SIDEBAR_ORGANISER.PREVIEW') }}
        </h2>
        <div
          v-for="entry in preview"
          :key="entry.name"
          class="flex flex-col gap-1"
        >
          <template v-if="entry.section">
            <span
              class="flex gap-2 items-center py-1 px-2 text-xs font-medium rounded text-n-slate-11"
            >
              <Icon
                v-if="entry.icon"
                :icon="entry.icon"
                class="flex-shrink-0 size-4"
              />
              <span class="flex-1 truncate">{{ entry.label }}</span>
              <span class="flex-shrink-0 i-lucide-chevron-down size-3" />
            </span>
            <span
              v-for="item in entry.items"
              :key="item.name"
              class="flex gap-2 items-center py-1 pl-4 pr-2 rounded text-[13px] text-n-slate-12"
            >
              <Icon
                :icon="item.icon || 'i-lucide-circle-small'"
                class="flex-shrink-0 size-4 text-n-slate-11"
              />
              <span class="truncate">{{ item.label }}</span>
              <span
                v-if="homeItem === item.name"
                class="flex-shrink-0 i-lucide-house size-3 text-n-slate-10"
              />
            </span>
          </template>
          <span
            v-else
            class="flex gap-2 items-center py-1 px-2 rounded text-[13px] text-n-slate-12"
          >
            <Icon
              :icon="entry.icon || 'i-lucide-circle-small'"
              class="flex-shrink-0 size-4 text-n-slate-11"
            />
            <span class="flex-1 truncate">{{ entry.label }}</span>
            <span
              v-if="homeItem === entry.name"
              class="flex-shrink-0 i-lucide-house size-3 text-n-slate-10"
            />
            <span
              v-if="entry.children"
              class="flex-shrink-0 i-lucide-chevron-down size-3 text-n-slate-10"
            />
          </span>
        </div>
      </aside>
    </div>
  </div>
</template>
