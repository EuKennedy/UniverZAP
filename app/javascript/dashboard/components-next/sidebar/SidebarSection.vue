<script setup>
/**
 * A section of the sidebar: a heading a super admin created, with menu entries
 * under it.
 *
 * It WRAPS its items rather than parenting them. Every item is rendered by the
 * same SidebarGroup the top level uses, so an item inside a section still has
 * its own three render levels — Conversas keeps Canais, and Canais keeps the
 * inboxes. That is the whole reason this component exists instead of a group
 * holding children: nesting SidebarGroup inside SidebarGroup spends a level
 * that the native groups have already spent, and the inboxes fall off the end.
 *
 * Open or closed is remembered per USER, in ui_settings, while the sections
 * themselves are defined per installation. The super admin decides what the
 * drawers are; each person decides which ones they keep open.
 */
import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useSidebarContext } from './provider';
import Icon from 'next/icon/Icon.vue';
import SidebarGroup from './SidebarGroup.vue';

const props = defineProps({
  name: { type: String, required: true },
  label: { type: String, required: true },
  icon: { type: [String, Object, Function], default: null },
  items: { type: Array, default: () => [] },
});

const { isCollapsed } = useSidebarContext();
const { uiSettings, updateUISettings } = useUISettings();

// Stored as the CLOSED ones, so a section created after this user last touched
// their settings arrives open. A list of open ones would hide every new section
// from everybody who already has the setting.
const closed = computed(() => uiSettings.value.sidebar_closed_sections || []);
const isOpen = computed(() => !closed.value.includes(props.name));

const toggle = () => {
  updateUISettings({
    sidebar_closed_sections: isOpen.value
      ? [...closed.value, props.name]
      : closed.value.filter(name => name !== props.name),
  });
};
</script>

<template>
  <li class="grid gap-1 list-none min-w-0">
    <!-- The rail is 56px wide: a heading has nowhere to render and nothing to
      collapse into, so the section steps aside and the icons stand on their
      own, exactly as they did before anybody grouped them. -->
    <button
      v-if="!isCollapsed"
      type="button"
      class="flex gap-2 items-center px-1.5 h-7 rounded-lg cursor-pointer select-none text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 min-w-0"
      :title="label"
      @click="toggle"
    >
      <Icon v-if="icon" :icon="icon" class="flex-shrink-0 size-4" />
      <span
        class="flex-1 text-xs font-medium tracking-wide truncate text-start"
      >
        {{ label }}
      </span>
      <span
        class="flex-shrink-0 transition-transform duration-150 i-lucide-chevron-down size-3"
        :class="{ '-rotate-90 rtl:rotate-90': !isOpen }"
      />
    </button>
    <ul
      v-show="isCollapsed || isOpen"
      class="flex flex-col gap-1 m-0 list-none min-w-0"
      :class="{ 'items-center': isCollapsed }"
    >
      <SidebarGroup v-for="item in items" :key="item.name" v-bind="item" />
    </ul>
  </li>
</template>
