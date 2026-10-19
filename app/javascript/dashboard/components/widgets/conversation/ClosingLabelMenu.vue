<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  labels: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const select = label => emit('select', label);
</script>

<template>
  <div
    class="flex flex-col gap-1 p-2 border rounded-lg shadow-lg border-n-strong dark:border-n-strong bg-n-alpha-3 backdrop-blur-[100px] min-w-[16rem] max-w-[20rem]"
    data-testid="closing-label-menu"
  >
    <p class="px-2 pt-1 mb-0 text-sm font-medium text-n-slate-12">
      {{ t('CONVERSATION.CLOSING_LABEL.TITLE') }}
    </p>
    <p class="px-2 mb-1 text-xs text-n-slate-11">
      {{ t('CONVERSATION.CLOSING_LABEL.DESCRIPTION') }}
    </p>
    <button
      v-for="label in labels"
      :key="label.id"
      type="button"
      :disabled="isLoading"
      class="flex items-start w-full gap-2 px-2 py-1.5 text-left rounded-md hover:bg-n-alpha-1 disabled:opacity-60 disabled:cursor-not-allowed"
      :data-testid="`closing-label-${label.title}`"
      @click="select(label)"
    >
      <span
        class="flex-shrink-0 mt-1 rounded-full size-3 border border-n-strong"
        :style="{ backgroundColor: label.color }"
      />
      <span class="flex flex-col min-w-0">
        <span class="text-sm text-n-slate-12 truncate">{{ label.title }}</span>
        <span
          v-if="label.description"
          class="text-xs text-n-slate-11 line-clamp-2"
        >
          {{ label.description }}
        </span>
      </span>
    </button>
  </div>
</template>
