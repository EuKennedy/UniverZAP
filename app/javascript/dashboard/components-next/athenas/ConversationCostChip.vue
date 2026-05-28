<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

// Per-conversation Athenas cost transparency chip. Renders only when
// the conversation has actually consumed AI tokens, so human-only
// threads stay free of clutter. Hover shows the precise BRL value
// with two decimals; the chip itself displays the rounded reais to
// keep visual weight low.
const props = defineProps({
  costCentsBrl: {
    type: Number,
    default: 0,
  },
});

const { t } = useI18n();

const visible = computed(() => Number(props.costCentsBrl) > 0);
const reais = computed(() => (Number(props.costCentsBrl) / 100).toFixed(2));
const integer = computed(() => Math.ceil(Number(props.costCentsBrl) / 100));
const tooltip = computed(() =>
  t('CONVERSATION.HEADER.ATHENAS_COST_TOOLTIP', { brl: reais.value })
);
</script>

<template>
  <span
    v-if="visible"
    v-tooltip.bottom="tooltip"
    class="inline-flex items-center gap-1.5 px-2 h-7 rounded-full bg-n-teal-3/40 text-n-teal-12 ring-1 ring-n-teal-7/40 text-[11px] font-medium tabular-nums cursor-help"
  >
    <Icon icon="i-lucide-sparkles" class="size-3 flex-shrink-0" />
    {{ `R$${integer}` }}
  </span>
</template>
