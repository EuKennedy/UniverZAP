<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useSidebarLayout } from 'dashboard/composables/useSidebarLayout';
import { applyLayout } from 'dashboard/components-next/sidebar/helper/applyLayout';
import SidebarLayoutAPI from 'dashboard/api/sidebarLayout';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
// The menu comes from the sidebar itself, so the preview runs on exactly what
// the real sidebar renders instead of a rebuilt guess.
const { layout: savedLayout, setLayout, menu } = useSidebarLayout();

// Lists, not a map of rules. Dragging is moving something out of one list and
// into another; modelling it any other way turns every drag into a translation.
const loose = ref([]);
const groups = ref([]);
const isSaving = ref(false);

// Generated, never borrowed from an item's `name`, so deleting a group can
// never take an item down with it.
const newGroupId = () => `g_${Date.now()}_${Math.floor(Math.random() * 1e4)}`;

const hydrate = () => {
  const saved = savedLayout.value || {};
  const rules = saved.items || {};
  // Every top-level entry, groups included: the sidebar renders three levels,
  // so a native group can live inside a custom one like anything else.
  const leaves = (menu.value || []).map(entry => ({
    name: entry.name,
    icon: entry.icon,
    original: entry.label,
    childCount: entry.children?.length || 0,
    label: rules[entry.name]?.label || '',
    hidden: Boolean(rules[entry.name]?.hidden),
  }));

  groups.value = (saved.groups || [])
    .slice()
    .sort((a, b) => a.order - b.order)
    .map(group => ({
      id: group.id,
      label: group.label,
      items: leaves.filter(item => rules[item.name]?.group === group.id),
    }));

  loose.value = leaves.filter(item => {
    const target = rules[item.name]?.group;
    return !target || !groups.value.some(group => group.id === target);
  });
};

// The sidebar publishes its menu a tick after this mounts, so build from it
// whenever it arrives.
watch(menu, hydrate, { immediate: true });

const draft = computed(() => {
  const items = {};
  const record = (item, groupId, index) => {
    items[item.name] = { order: index };
    if (groupId) items[item.name].group = groupId;
    if (item.hidden) items[item.name].hidden = true;
    if (item.label) items[item.name].label = item.label;
  };
  loose.value.forEach((item, index) => record(item, null, index));
  groups.value.forEach(group =>
    group.items.forEach((item, index) => record(item, group.id, index))
  );
  return {
    version: 1,
    groups: groups.value.map((group, index) => ({
      id: group.id,
      label: group.label,
      order: index,
    })),
    items,
  };
});

// The same function the sidebar runs. Anything else would preview a menu nobody
// will ever see.
const preview = computed(() => applyLayout(menu.value, draft.value));

const addGroup = () => {
  groups.value.push({
    id: newGroupId(),
    label: t('SIDEBAR_ORGANISER.NEW_GROUP'),
    items: [],
  });
};

const removeGroup = id => {
  const group = groups.value.find(candidate => candidate.id === id);
  // The items go home rather than down with the group.
  if (group) loose.value.push(...group.items);
  groups.value = groups.value.filter(candidate => candidate.id !== id);
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
  loose.value = [...loose.value, ...groups.value.flatMap(group => group.items)];
  groups.value = [];
  loose.value.forEach(item => {
    item.hidden = false;
    item.label = '';
  });
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

    <div class="grid grid-cols-1 xl:grid-cols-[1fr_18rem] gap-6 items-start">
      <div class="flex flex-col gap-6">
        <section class="flex flex-col gap-2">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('SIDEBAR_ORGANISER.LOOSE') }}
          </h2>
          <p class="m-0 text-[13px] text-n-slate-11">
            {{ t('SIDEBAR_ORGANISER.LOOSE_HINT') }}
          </p>
          <Draggable
            v-model="loose"
            group="menu"
            item-key="name"
            tag="ul"
            class="flex flex-col gap-1 p-2 rounded-lg border border-dashed min-h-16 border-n-weak"
          >
            <template #item="{ element }">
              <li
                class="flex gap-2 items-center py-1.5 px-2 rounded-md cursor-grab bg-n-solid-2"
              >
                <Icon
                  icon="i-lucide-grip-vertical"
                  class="flex-shrink-0 size-4 text-n-slate-10"
                />
                <Icon
                  :icon="element.icon || 'i-lucide-circle-small'"
                  class="flex-shrink-0 size-4 text-n-slate-11"
                />
                <input
                  v-model="element.label"
                  :placeholder="element.original"
                  class="flex-1 min-w-0 px-2 h-7 rounded outline-none text-[13px] bg-transparent text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
                />
                <span
                  v-if="element.childCount"
                  class="flex-shrink-0 px-1.5 text-[11px] rounded-full text-n-slate-11 bg-n-alpha-1"
                  :title="t('SIDEBAR_ORGANISER.CARRIES_TABS')"
                >
                  {{ element.childCount }}
                </span>
                <Button
                  size="xs"
                  variant="ghost"
                  :color="element.hidden ? 'ruby' : 'slate'"
                  :icon="element.hidden ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                  @click="element.hidden = !element.hidden"
                />
              </li>
            </template>
          </Draggable>
        </section>

        <section class="flex flex-col gap-3">
          <div class="flex justify-between items-center">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('SIDEBAR_ORGANISER.GROUPS') }}
            </h2>
            <Button
              size="sm"
              variant="ghost"
              icon="i-lucide-plus"
              :label="t('SIDEBAR_ORGANISER.ADD_GROUP')"
              @click="addGroup"
            />
          </div>

          <p v-if="!groups.length" class="m-0 text-[13px] text-n-slate-11">
            {{ t('SIDEBAR_ORGANISER.NO_GROUPS') }}
          </p>

          <div
            v-for="group in groups"
            :key="group.id"
            class="flex flex-col gap-2 p-3 rounded-lg border border-n-weak bg-n-solid-1"
          >
            <div class="flex gap-2 items-center">
              <Icon
                icon="i-lucide-folder"
                class="flex-shrink-0 size-4 text-n-slate-11"
              />
              <input
                v-model="group.label"
                :placeholder="t('SIDEBAR_ORGANISER.GROUP_NAME')"
                class="flex-1 px-2 h-8 min-w-0 text-sm font-medium bg-transparent rounded outline-none text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
              />
              <Button
                size="xs"
                variant="ghost"
                color="ruby"
                icon="i-lucide-trash-2"
                @click="removeGroup(group.id)"
              />
            </div>

            <Draggable
              v-model="group.items"
              group="menu"
              item-key="name"
              tag="ul"
              class="flex flex-col gap-1 p-2 rounded-md border border-dashed min-h-12 border-n-weak"
            >
              <template #item="{ element }">
                <li
                  class="flex gap-2 items-center py-1.5 px-2 rounded-md cursor-grab bg-n-solid-2"
                >
                  <Icon
                    icon="i-lucide-grip-vertical"
                    class="flex-shrink-0 size-4 text-n-slate-10"
                  />
                  <Icon
                    :icon="element.icon || 'i-lucide-circle-small'"
                    class="flex-shrink-0 size-4 text-n-slate-11"
                  />
                  <input
                    v-model="element.label"
                    :placeholder="element.original"
                    class="flex-1 min-w-0 px-2 h-7 rounded outline-none text-[13px] bg-transparent text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
                  />
                  <span
                    v-if="element.childCount"
                    class="flex-shrink-0 px-1.5 text-[11px] rounded-full text-n-slate-11 bg-n-alpha-1"
                    :title="t('SIDEBAR_ORGANISER.CARRIES_TABS')"
                  >
                    {{ element.childCount }}
                  </span>
                  <Button
                    size="xs"
                    variant="ghost"
                    :color="element.hidden ? 'ruby' : 'slate'"
                    :icon="element.hidden ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                    @click="element.hidden = !element.hidden"
                  />
                </li>
              </template>
            </Draggable>

            <p
              v-if="!group.items.length"
              class="m-0 text-[12px] text-n-slate-10"
            >
              {{ t('SIDEBAR_ORGANISER.DROP_HERE') }}
            </p>
          </div>
        </section>
      </div>

      <aside
        class="flex sticky top-6 flex-col gap-1 p-3 rounded-lg border border-n-weak bg-n-solid-1"
      >
        <h2 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('SIDEBAR_ORGANISER.PREVIEW') }}
        </h2>
        <div
          v-for="entry in preview"
          :key="entry.name"
          class="flex flex-col gap-1"
        >
          <span
            class="flex gap-2 items-center py-1 px-2 rounded text-[13px] text-n-slate-12"
            :class="entry.children ? 'font-medium' : ''"
          >
            <Icon
              :icon="entry.icon || 'i-lucide-circle-small'"
              class="flex-shrink-0 size-4 text-n-slate-11"
            />
            <span class="truncate">{{ entry.label }}</span>
          </span>
          <span
            v-for="child in entry.children || []"
            :key="child.name"
            class="pl-8 text-[12px] truncate text-n-slate-11"
          >
            {{ child.label }}
          </span>
        </div>
      </aside>
    </div>
  </div>
</template>
