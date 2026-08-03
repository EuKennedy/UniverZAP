<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';
import Button from 'dashboard/components-next/button/Button.vue';

// Compact balance line for the agents hub. The full 3-card catalogue used to
// sit inline and take the whole fold, which pushed the agents (the subject of
// the page) below it: you opened "Agente de IA" and the first thing the screen
// sold you was credit. The catalogue already exists as a modal, so this strip
// keeps the balance visible (low balance must never be hidden) and defers the
// buying flow to a click.
const { t } = useI18n();
const {
  balanceCents,
  balanceBrl,
  daysRemaining,
  status,
  refresh,
  openTopUpModal,
} = useAthenasCredits();

onMounted(() => refresh({ force: true }));

const balanceWhole = computed(() =>
  Math.floor((balanceCents.value || 0) / 100)
);
const cents = computed(() => balanceBrl.value.split('.')[1] || '00');

const tone = computed(() => {
  if (status.value === 'exhausted') return 'ruby';
  if (status.value === 'warn_95' || status.value === 'warn_80') return 'amber';
  return 'teal';
});

// Only the balance figure carries the tone. A whole card turning red for a
// routine low balance reads as an outage.
const balanceClass = computed(
  () =>
    ({
      teal: 'text-n-slate-12',
      amber: 'text-n-amber-11',
      ruby: 'text-n-ruby-11',
    })[tone.value]
);

const dotClass = computed(
  () =>
    ({
      teal: 'bg-n-teal-9',
      amber: 'bg-n-amber-9',
      ruby: 'bg-n-ruby-9',
    })[tone.value]
);
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 flex-wrap px-4 py-3 rounded-xl bg-n-solid-1 ring-1 ring-n-weak"
  >
    <div class="flex items-center gap-3 min-w-0">
      <span class="size-2 rounded-full flex-shrink-0" :class="dotClass" />
      <div class="flex items-baseline gap-1.5 min-w-0">
        <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
          {{ t('ATHENAS.CREDITS_STRIP.BALANCE') }}
        </span>
        <span
          class="text-base font-semibold tabular-nums"
          :class="balanceClass"
        >
          {{ `R$ ${balanceWhole},${cents}` }}
        </span>
      </div>
      <span
        v-if="daysRemaining"
        class="text-[12px] text-n-slate-10 tabular-nums whitespace-nowrap"
      >
        {{ t('ATHENAS.CREDITS_STRIP.DAYS', { n: daysRemaining }) }}
      </span>
    </div>
    <Button
      variant="ghost"
      size="sm"
      icon="i-lucide-plus"
      :label="t('ATHENAS.CREDITS_STRIP.TOP_UP')"
      @click="openTopUpModal('athenas_hub')"
    />
  </div>
</template>
