<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';

// Circular saldo chip — sits above the Onboarding launcher and Copilot
// FAB (z-50 stack: copilot bottom-4, onboarding bottom-20, this at
// bottom-36). Kept perfectly 1:1 so it doesn't compete visually with
// the chat content; the operator gets the balance number at a glance,
// the colour-coded surface telegraphs status, and the tooltip carries
// the long-form copy on hover. One click opens the top-up modal.
const { t } = useI18n();
const {
  isLoaded,
  status,
  balanceCents,
  balanceBrl,
  daysRemaining,
  openTopUpModal,
} = useAthenasCredits();

const tone = computed(() => {
  if (status.value === 'exhausted') return 'ruby';
  if (status.value === 'warn_95') return 'amber';
  if (status.value === 'warn_80') return 'amber';
  return 'teal';
});

const chipCls = computed(() => {
  const map = {
    teal: 'bg-n-teal-3/80 text-n-teal-12 ring-n-teal-7/60 hover:bg-n-teal-3',
    amber:
      'bg-n-amber-3/80 text-n-amber-12 ring-n-amber-7/60 hover:bg-n-amber-3',
    ruby: 'bg-n-ruby-3/85 text-n-ruby-12 ring-n-ruby-7/60 hover:bg-n-ruby-3',
  };
  return map[tone.value];
});

// Inteiros para caber no círculo. Tooltip carrega o saldo com centavos
// + estimativa de dias para quem precisar do detalhe.
const balanceWhole = computed(() =>
  Math.floor((balanceCents.value || 0) / 100)
);

const tooltip = computed(() => {
  const balance = t('ATHENAS_CREDITS.METER.TOOLTIP_BALANCE', {
    balance: balanceBrl.value,
  });
  if (daysRemaining.value === null || daysRemaining.value === undefined)
    return balance;
  return `${balance} · ${t('ATHENAS_CREDITS.METER.TOOLTIP_DAYS', { days: daysRemaining.value })}`;
});
</script>

<template>
  <button
    v-if="isLoaded"
    v-tooltip.left="tooltip"
    type="button"
    class="fixed bottom-36 ltr:right-4 rtl:left-4 z-50 flex items-center justify-center size-14 rounded-full ring-1 shadow-lg backdrop-blur-md text-[13px] font-semibold tabular-nums transition-all duration-200 motion-safe:hover:scale-[1.06] cursor-pointer"
    :class="chipCls"
    :aria-label="t('ATHENAS_CREDITS.METER.ARIA_LABEL', { balance: balanceBrl })"
    @click="openTopUpModal('meter_chip')"
  >
    {{ `R$${balanceWhole}` }}
  </button>
</template>
