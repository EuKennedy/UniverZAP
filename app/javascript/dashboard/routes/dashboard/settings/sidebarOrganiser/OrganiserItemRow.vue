<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// One entry of the menu in the organiser: its name, its short name on the rail,
// and, for an entry that carries pages, the pages themselves. Every entry with
// pages shares one drag group, which is what lets a page change section.
const props = defineProps({
  item: { type: Object, required: true },
  isHome: { type: Boolean, default: false },
});

const emit = defineEmits(['toggleHome']);

const { t } = useI18n();
const row = computed(() => props.item);
const open = ref(false);
</script>

<template>
  <div class="flex flex-col gap-1 rounded-md bg-n-solid-2">
    <div class="flex gap-2 items-center py-1.5 px-2">
      <Icon
        icon="i-lucide-grip-vertical"
        class="flex-shrink-0 cursor-grab drag-handle size-4 text-n-slate-10"
      />
      <Icon
        :icon="row.icon || 'i-lucide-circle-small'"
        class="flex-shrink-0 size-4 text-n-slate-11"
      />
      <input
        v-model="row.label"
        :placeholder="row.original"
        class="flex-1 min-w-0 px-2 h-7 rounded outline-none text-[13px] bg-transparent text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
      />
      <input
        v-model="row.railLabel"
        :placeholder="t('SIDEBAR_ORGANISER.RAIL_NAME')"
        :title="t('SIDEBAR_ORGANISER.RAIL_NAME_HINT')"
        maxlength="12"
        class="flex-shrink-0 px-2 w-24 h-7 rounded outline-none text-xs bg-transparent text-n-slate-11 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
      />
      <button
        v-if="row.pages"
        type="button"
        class="flex flex-shrink-0 gap-1 items-center px-1.5 h-6 text-[11px] rounded-full text-n-slate-11 bg-n-alpha-1 hover:bg-n-alpha-2"
        :title="t('SIDEBAR_ORGANISER.CARRIES_TABS')"
        :aria-expanded="open"
        @click="open = !open"
      >
        {{ row.pages.length }}
        <span
          class="transition-transform size-3 i-lucide-chevron-down"
          :class="{ 'rotate-180': open }"
        />
      </button>
      <Button
        v-if="row.route"
        size="xs"
        variant="ghost"
        :color="isHome ? 'blue' : 'slate'"
        :icon="isHome ? 'i-lucide-house' : 'i-lucide-house-plus'"
        :title="t('SIDEBAR_ORGANISER.HOME')"
        @click="emit('toggleHome', row)"
      />
      <Button
        size="xs"
        variant="ghost"
        :color="row.hidden ? 'ruby' : 'slate'"
        :icon="row.hidden ? 'i-lucide-eye-off' : 'i-lucide-eye'"
        @click="row.hidden = !row.hidden"
      />
    </div>

    <Draggable
      v-if="row.pages && open"
      v-model="row.pages"
      group="pages"
      item-key="id"
      handle=".page-handle"
      tag="ul"
      class="flex flex-col gap-0.5 px-2 pb-2 mb-0 ms-6 min-h-8 list-none"
    >
      <template #item="{ element: page }">
        <li
          class="flex gap-2 items-center px-1.5 h-8 rounded list-none bg-n-solid-1"
        >
          <Icon
            icon="i-lucide-grip-vertical"
            class="flex-shrink-0 cursor-grab page-handle size-3.5 text-n-slate-10"
          />
          <input
            v-model="page.label"
            :placeholder="page.original"
            class="flex-1 min-w-0 px-1.5 h-6 rounded outline-none text-xs bg-transparent text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
          />
          <Button
            size="xs"
            variant="ghost"
            :color="page.hidden ? 'ruby' : 'slate'"
            :icon="page.hidden ? 'i-lucide-eye-off' : 'i-lucide-eye'"
            :title="t('SIDEBAR_ORGANISER.HIDE_PAGE')"
            @click="page.hidden = !page.hidden"
          />
        </li>
      </template>
    </Draggable>
  </div>
</template>
