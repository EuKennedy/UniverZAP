<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  totalCount: {
    type: Number,
    default: 0,
  },
  groupBy: {
    type: String,
    default: 'urgency',
  },
});

const emit = defineEmits(['create', 'refresh', 'groupBy']);

const { t } = useI18n();

const GROUP_OPTIONS = [
  { value: 'urgency', labelKey: 'TASKS.GROUP_BY.URGENCY' },
  { value: 'status', labelKey: 'TASKS.GROUP_BY.STATUS' },
  { value: 'none', labelKey: 'TASKS.GROUP_BY.NONE' },
];

const isGroupOpen = ref(false);

const currentLabel = computed(() => {
  const found = GROUP_OPTIONS.find(o => o.value === props.groupBy);
  return found ? t(found.labelKey) : t('TASKS.GROUP_BY.NONE');
});

const selectGroup = value => {
  emit('groupBy', value);
  isGroupOpen.value = false;
};

const closeGroup = () => {
  isGroupOpen.value = false;
};
</script>

<template>
  <header
    class="flex-shrink-0 flex items-center gap-3 h-14 px-6 border-b border-n-weak bg-n-background sticky top-0 z-10"
  >
    <div class="flex items-center gap-2.5 min-w-0">
      <span
        class="size-7 grid place-content-center rounded-lg bg-gradient-to-br from-n-iris-9/20 to-n-iris-9/[0.04] ring-1 ring-n-weak flex-shrink-0"
      >
        <span class="i-lucide-list-checks size-4 text-n-iris-11" />
      </span>
      <div class="flex items-baseline gap-2 min-w-0">
        <h1 class="text-[15px] font-semibold text-n-slate-12 tracking-tight">
          {{ t('TASKS.TITLE') }}
        </h1>
        <span
          v-if="totalCount > 0"
          class="text-[11px] tabular-nums px-1.5 h-4 inline-flex items-center rounded-md bg-n-alpha-1 text-n-slate-11 ring-1 ring-inset ring-n-weak"
        >
          {{ totalCount }}
        </span>
      </div>
    </div>

    <div class="ml-auto flex items-center gap-2">
      <div v-on-click-outside="closeGroup" class="relative">
        <Button
          icon="i-lucide-layers"
          size="sm"
          outline
          slate
          @click="isGroupOpen = !isGroupOpen"
        >
          <span class="hidden sm:inline">
            {{ `${t('TASKS.GROUP_BY.LABEL')}: ${currentLabel}` }}
          </span>
          <span class="sm:hidden">{{ currentLabel }}</span>
        </Button>
        <ul
          v-if="isGroupOpen"
          class="absolute right-0 top-full mt-1.5 min-w-[180px] py-1 list-none m-0 rounded-xl bg-n-solid-1 ring-1 ring-n-weak shadow-xl z-20"
        >
          <li v-for="option in GROUP_OPTIONS" :key="option.value">
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm hover:bg-n-alpha-1 text-n-slate-12"
              @click="selectGroup(option.value)"
            >
              <span
                v-if="option.value === groupBy"
                class="i-lucide-check size-3.5 text-n-teal-11"
              />
              <span v-else class="size-3.5" />
              {{ t(option.labelKey) }}
            </button>
          </li>
        </ul>
      </div>

      <Button
        icon="i-lucide-refresh-cw"
        size="sm"
        ghost
        slate
        :aria-label="t('TASKS.REFRESH')"
        @click="emit('refresh')"
      />

      <Button
        icon="i-lucide-plus"
        :label="t('TASKS.NEW_TASK')"
        size="sm"
        solid
        blue
        data-test-id="tasks-header-create"
        @click="emit('create')"
      />
    </div>
  </header>
</template>
