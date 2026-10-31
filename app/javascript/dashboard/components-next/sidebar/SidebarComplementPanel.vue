<script setup>
import { computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useSidebarContext } from './provider';
import GlassNavPanel from './GlassNavPanel.vue';

// UniverZAP: the pages of the section the rail has open. Reads the menu the
// sidebar already built, so permissions, plan and the super admin's layout are
// the same in both. The conversations screen has its own panel, with the queues.
const props = defineProps({
  menu: { type: Array, required: true },
});

const emit = defineEmits(['update:visible']);

const route = useRoute();
const router = useRouter();
const { isAllowed } = useSidebarContext();
const { uiSettings, updateUISettings } = useUISettings();

// A super admin's section wraps entries of the menu: the rail shows those.
const groups = computed(() =>
  props.menu.flatMap(item => (item.section ? item.items : [item]))
);

const routeName = to => (to ? router.resolve(to).name : null);

const leavesOf = group =>
  (group.children || []).flatMap(child =>
    child.children ? leavesOf(child) : [child]
  );

const isCurrent = leaf =>
  routeName(leaf.to) === route.name || leaf.activeOn?.includes(route.name);

const activeGroup = computed(() =>
  groups.value.find(group => leavesOf(group).some(isCurrent))
);

const toItem = child => ({
  key: child.name,
  name: child.label,
  icon: child.icon,
  to: child.to,
  active: isCurrent(child),
});

const sections = computed(() => {
  const group = activeGroup.value;
  if (!group) return [];
  const direct = group.children.filter(
    child => !child.children && child.to && isAllowed(child.to)
  );
  const nested = group.children
    .filter(child => child.children?.length)
    .map(child => ({
      key: child.name,
      title: child.label,
      items: child.children
        .filter(leaf => leaf.to && isAllowed(leaf.to))
        .map(toItem),
    }))
    .filter(section => section.items.length);
  return [
    ...(direct.length ? [{ key: group.name, items: direct.map(toItem) }] : []),
    ...nested,
  ];
});

const visible = computed(() => sections.value.length > 0);
watch(visible, value => emit('update:visible', value), { immediate: true });

const collapsed = computed(
  () => !!uiSettings.value.conversation_quick_nav_collapsed
);

const toggle = () =>
  updateUISettings({ conversation_quick_nav_collapsed: !collapsed.value });

const open = item => router.push(item.to);
</script>

<template>
  <GlassNavPanel
    v-if="visible"
    :title="activeGroup.label"
    :sections="sections"
    :collapsed="collapsed"
    @select="open"
    @toggle="toggle"
  />
</template>
