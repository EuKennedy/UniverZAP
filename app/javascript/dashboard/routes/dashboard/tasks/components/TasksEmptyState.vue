<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // `default` = nothing in the account yet, `filtered` = filters hid everything.
  variant: {
    type: String,
    default: 'default',
    validator: value => ['default', 'filtered'].includes(value),
  },
});

const emit = defineEmits(['create', 'reset']);

const { t } = useI18n();

const titleKey = computed(() =>
  props.variant === 'filtered'
    ? 'TASKS.EMPTY.FILTERED_TITLE'
    : 'TASKS.EMPTY.TITLE'
);
const descriptionKey = computed(() =>
  props.variant === 'filtered'
    ? 'TASKS.EMPTY.FILTERED_DESCRIPTION'
    : 'TASKS.EMPTY.DESCRIPTION'
);
</script>

<template>
  <section
    class="flex flex-col items-center justify-center gap-6 py-20 px-8 text-center"
  >
    <div
      class="size-20 rounded-3xl bg-gradient-to-br from-n-iris-9/20 to-n-iris-9/[0.04] ring-1 ring-n-weak flex items-center justify-center"
    >
      <span class="i-lucide-list-checks size-9 text-n-iris-11" />
    </div>
    <div class="flex flex-col gap-2 max-w-md">
      <h2 class="text-xl font-semibold text-n-slate-12 tracking-tight">
        {{ t(titleKey) }}
      </h2>
      <p class="text-sm text-n-slate-11 leading-relaxed">
        {{ t(descriptionKey) }}
      </p>
    </div>
    <Button
      v-if="variant === 'default'"
      icon="i-lucide-plus"
      :label="t('TASKS.EMPTY.CTA')"
      size="sm"
      solid
      blue
      @click="emit('create')"
    />
    <Button
      v-else
      icon="i-lucide-filter-x"
      :label="t('TASKS.FILTERS.CLEAR')"
      size="sm"
      outline
      slate
      @click="emit('reset')"
    />
  </section>
</template>
