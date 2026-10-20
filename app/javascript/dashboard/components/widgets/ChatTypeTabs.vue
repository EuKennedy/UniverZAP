<script setup>
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';
import {
  DropdownContainer,
  DropdownBody,
  DropdownItem,
} from 'dashboard/components-next/dropdown-menu/base';

// Each item is { key, name, count } and may carry `options` (same shape) with
// `activeOption`: the tab then shows the chosen option and a menu to switch it.
const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: wootConstants.ASSIGNEE_TYPE.ALL,
  },
});

const emit = defineEmits(['chatTabChange', 'optionChange']);

const activeTabIndex = computed(() => {
  return props.items.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  const selectedItem = props.items[selectedTabIndex];
  if (selectedItem && selectedItem.key !== props.activeTab) {
    emit('chatTabChange', selectedItem.key);
  }
};

const selectedOption = item => {
  return item.options?.find(option => option.key === item.activeOption);
};

// Choosing an option also means showing its tab: the parent resolves both from
// this one event, so it never fetches a bucket it is about to leave.
const onOptionClick = option => {
  emit('optionChange', option.key);
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      const nextIndex = (activeTabIndex.value + 1) % props.items.length;
      onTabChange(nextIndex);
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <div
    class="flex items-center w-full h-10 gap-1 px-3 -mt-1 border-b border-n-weak"
  >
    <ul class="flex items-center flex-1 min-w-0 gap-4 mb-0 list-none">
      <li v-for="(item, index) in items" :key="item.key" class="flex-shrink-0">
        <DropdownContainer>
          <template #trigger="{ toggle, isOpen }">
            <button
              type="button"
              class="relative flex items-center gap-1 py-2.5 text-sm font-medium select-none after:absolute after:bottom-px after:left-0 after:right-0 after:h-[2px] after:rounded-full after:transition-all after:duration-200 hover:text-n-slate-12"
              :class="
                item.key === activeTab
                  ? 'text-n-teal-11 after:bg-brand-gradient after:opacity-100'
                  : 'text-n-slate-11 after:bg-transparent after:opacity-0'
              "
              :aria-expanded="item.options ? isOpen : undefined"
              @click="
                item.options && item.key === activeTab
                  ? toggle()
                  : onTabChange(index)
              "
            >
              {{ selectedOption(item)?.name || item.name }}
              <span
                class="rounded-full h-5 flex items-center justify-center text-xs font-medium px-1.5 min-w-[20px]"
                :class="
                  item.key === activeTab
                    ? 'bg-brand-gradient-soft text-n-teal-11'
                    : 'bg-n-alpha-1 text-n-slate-10'
                "
              >
                {{ selectedOption(item)?.count ?? item.count }}
              </span>
              <span
                v-if="item.options"
                class="i-lucide-chevron-down size-3.5 transition-transform duration-200"
                :class="{ 'rotate-180': isOpen }"
                @click.stop="toggle()"
              />
            </button>
          </template>
          <DropdownBody v-if="item.options" class="top-1 min-w-48 z-50" strong>
            <DropdownItem
              v-for="option in item.options"
              :key="option.key"
              class="justify-between cursor-pointer"
              @click="onOptionClick(option)"
            >
              <template #label>
                <span class="flex items-center justify-between w-full gap-3">
                  <span
                    :class="
                      option.key === item.activeOption && item.key === activeTab
                        ? 'text-n-teal-11 font-medium'
                        : 'text-n-slate-12'
                    "
                  >
                    {{ option.name }}
                  </span>
                  <span class="text-xs text-n-slate-10">
                    {{ option.count }}
                  </span>
                </span>
              </template>
            </DropdownItem>
          </DropdownBody>
        </DropdownContainer>
      </li>
    </ul>
    <slot />
  </div>
</template>
