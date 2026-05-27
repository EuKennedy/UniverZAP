<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';
import Icon from 'next/icon/Icon.vue';

// Floating chip that sits above the Onboarding launcher and the Copilot
// FAB (z-50 stack: copilot bottom-4, onboarding bottom-20, this one
// bottom-36). One-click manual top-up plus a colour-coded balance
// readout so the operator always knows where they stand without
// opening a settings page.
const { t } = useI18n();
const { isLoaded, status, balanceBrl, daysRemaining, openTopUpModal } =
  useAthenasCredits();

const tone = computed(() => {
  if (status.value === 'exhausted') return 'ruby';
  if (status.value === 'warn_95') return 'amber';
  if (status.value === 'warn_80') return 'amber';
  return 'teal';
});

const chipCls = computed(() => {
  const map = {
    teal: 'bg-n-teal-3/70 text-n-teal-12 ring-n-teal-7/60 hover:bg-n-teal-3',
    amber:
      'bg-n-amber-3/70 text-n-amber-12 ring-n-amber-7/60 hover:bg-n-amber-3',
    ruby: 'bg-n-ruby-3/80 text-n-ruby-12 ring-n-ruby-7/60 hover:bg-n-ruby-3',
  };
  return map[tone.value];
});

const dotCls = computed(() => {
  const map = {
    teal: 'bg-n-teal-9',
    amber: 'bg-n-amber-9 motion-safe:animate-pulse',
    ruby: 'bg-n-ruby-9 motion-safe:animate-pulse',
  };
  return map[tone.value];
});

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
    class="fixed bottom-36 ltr:right-4 rtl:left-4 z-50 inline-flex items-center gap-2 px-3 h-9 rounded-full ring-1 shadow-lg backdrop-blur-md text-[12px] font-semibold transition-all duration-200 motion-safe:hover:scale-[1.04] cursor-pointer"
    :class="chipCls"
    :aria-label="t('ATHENAS_CREDITS.METER.ARIA_LABEL', { balance: balanceBrl })"
    @click="openTopUpModal('meter_chip')"
  >
    <span
      class="size-1.5 rounded-full flex-shrink-0"
      :class="dotCls"
      aria-hidden="true"
    />
    <Icon icon="i-lucide-sparkles" class="size-3.5" />
    <span class="tabular-nums">{{ `R$ ${balanceBrl}` }}</span>
  </button>
</template>
