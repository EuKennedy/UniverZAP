<script setup>
import { computed } from 'vue';
import { useStorage } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';
import SidebarGroupLeaf from './SidebarGroupLeaf.vue';

// UniverZAP: one group of "Canais" (WhatsApp >, Instagram >…), folded by
// default. A folded group still shows its active inbox, like every sidebar
// group does.
const props = defineProps({
  name: { type: String, required: true },
  label: { type: String, required: true },
  icon: { type: [Object, String], required: true },
  children: { type: Array, required: true },
  isExpanded: { type: Boolean, default: false },
  activeChild: { type: Object, default: undefined },
});

// Which groups the agent unfolded, kept across reloads.
const openGroups = useStorage('univerzap.sidebar.openChannelGroups', []);

const isOpen = computed(() => openGroups.value.includes(props.name));

const isActive = child => props.activeChild?.name === child.name;

const hasActiveChild = computed(() => props.children.some(isActive));

const toggle = () => {
  openGroups.value = isOpen.value
    ? openGroups.value.filter(name => name !== props.name)
    : [...openGroups.value, props.name];
};
</script>

<template>
  <li
    v-show="isExpanded || hasActiveChild"
    class="m-0 list-none ltr:ml-3 rtl:mr-3 min-w-0"
  >
    <button
      v-show="isExpanded"
      type="button"
      class="flex items-center w-full h-8 gap-2 px-2 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 min-w-0"
      :aria-expanded="isOpen"
      @click="toggle"
    >
      <Icon :icon="icon" class="flex-shrink-0 size-4" />
      <span class="flex-1 text-sm truncate text-start">{{ label }}</span>
      <span class="text-xs text-n-slate-10">{{ children.length }}</span>
      <span
        class="flex-shrink-0 transition-transform duration-200 i-lucide-chevron-right size-3.5 rtl:rotate-180"
        :class="{ '!rotate-90': isOpen }"
      />
    </button>
    <ul class="m-0 list-none reset-base min-w-0">
      <SidebarGroupLeaf
        v-for="child in children"
        v-show="(isExpanded && isOpen) || isActive(child)"
        v-bind="child"
        :key="child.name"
        :active="isActive(child)"
      />
    </ul>
  </li>
</template>
