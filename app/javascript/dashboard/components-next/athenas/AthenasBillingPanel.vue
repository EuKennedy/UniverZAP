<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';
import Icon from 'next/icon/Icon.vue';

// Inline billing surface for the Athenas Settings page. Mirrors the
// paywall modal's 3-card catalogue but lives ON the page (no modal
// dance) so the operator can buy more credits without leaving the
// Athenas hub. Reuses the same `useAthenasCredits` composable so
// the saldo + packages stay in sync with the modal version.
const { t } = useI18n();
const {
  balanceCents,
  balanceBrl,
  packages,
  status,
  daysRemaining,
  burnRatePerDay,
  refresh,
} = useAthenasCredits();

onMounted(() => refresh({ force: true }));

const balanceWhole = computed(() =>
  Math.floor((balanceCents.value || 0) / 100)
);

const statusTone = computed(() => {
  if (status.value === 'exhausted') return 'ruby';
  if (status.value === 'warn_95' || status.value === 'warn_80') return 'amber';
  return 'teal';
});

const balanceCardCls = computed(() => {
  const map = {
    teal: 'from-n-teal-9/20 via-n-teal-9/[0.06] to-transparent ring-n-teal-7/40',
    amber:
      'from-n-amber-9/20 via-n-amber-9/[0.06] to-transparent ring-n-amber-7/40',
    ruby: 'from-n-ruby-9/24 via-n-ruby-9/[0.08] to-transparent ring-n-ruby-7/40',
  };
  return map[statusTone.value];
});

const statusLabel = computed(() => {
  const map = {
    ok: t('ATHENAS_CREDITS.BILLING.STATUS.OK'),
    warn_80: t('ATHENAS_CREDITS.BILLING.STATUS.WARN_80'),
    warn_95: t('ATHENAS_CREDITS.BILLING.STATUS.WARN_95'),
    exhausted: t('ATHENAS_CREDITS.BILLING.STATUS.EXHAUSTED'),
  };
  return map[status.value] || map.ok;
});

const formatBrlShort = cents => `R$ ${Math.round(cents / 100)}`;
const formatBrlPrecise = cents =>
  `R$ ${(cents / 100).toFixed(2).replace('.', ',')}`;

const badgeMeta = badge => {
  if (badge === 'popular') {
    return {
      label: t('ATHENAS_CREDITS.MODAL.BADGE.POPULAR'),
      cls: 'bg-gradient-to-r from-n-teal-9 to-n-teal-10 text-white',
      icon: 'i-lucide-zap',
    };
  }
  if (badge === 'best_value') {
    return {
      label: t('ATHENAS_CREDITS.MODAL.BADGE.BEST_VALUE'),
      cls: 'bg-gradient-to-r from-n-amber-9 to-n-amber-10 text-white',
      icon: 'i-lucide-crown',
    };
  }
  return null;
};

const onCheckout = pkg => {
  // Pre-prime the meter so when the operator returns from Univercart
  // the saldo here is already fresh.
  refresh({ force: true });
  window.open(pkg.checkout_url, '_blank', 'noopener,noreferrer');
};
</script>

<template>
  <section class="px-10 pt-6 pb-2">
    <header class="flex items-center justify-between flex-wrap gap-3 mb-4">
      <div class="flex flex-col gap-1">
        <p
          class="text-[11px] font-bold uppercase tracking-[0.18em] text-n-teal-11"
        >
          {{ t('ATHENAS_CREDITS.BILLING.EYEBROW') }}
        </p>
        <h2
          class="text-lg font-semibold text-n-slate-12 m-0 tracking-tight leading-tight"
        >
          {{ t('ATHENAS_CREDITS.BILLING.TITLE') }}
        </h2>
      </div>
    </header>

    <div
      class="rounded-2xl border border-n-weak bg-gradient-to-br p-5 ring-1 mb-5"
      :class="balanceCardCls"
    >
      <div class="flex items-end justify-between flex-wrap gap-4">
        <div class="flex flex-col gap-1">
          <p
            class="text-[10px] font-bold uppercase tracking-[0.18em] text-n-slate-10 m-0"
          >
            {{ t('ATHENAS_CREDITS.BILLING.BALANCE_LABEL') }}
          </p>
          <p
            class="text-[34px] font-bold text-n-slate-12 leading-none tabular-nums m-0"
          >
            {{ `R$ ${balanceWhole}` }}
            <span class="text-[14px] font-medium text-n-slate-11 tabular-nums">
              ,{{ balanceBrl.split('.')[1] || '00' }}
            </span>
          </p>
          <p class="text-[12px] text-n-slate-11 m-0 mt-1">
            {{ statusLabel }}
          </p>
        </div>
        <div class="flex flex-col gap-1 items-end">
          <p
            class="text-[10px] font-bold uppercase tracking-[0.18em] text-n-slate-10 m-0"
          >
            {{ t('ATHENAS_CREDITS.BILLING.BURN_LABEL') }}
          </p>
          <p class="text-base font-semibold text-n-slate-12 m-0 tabular-nums">
            {{ `${formatBrlShort(burnRatePerDay)}/d` }}
          </p>
          <p
            v-if="daysRemaining !== null && daysRemaining !== undefined"
            class="text-[12px] text-n-slate-11 m-0 tabular-nums"
          >
            {{
              t('ATHENAS_CREDITS.BILLING.DAYS_LEFT', { days: daysRemaining })
            }}
          </p>
        </div>
      </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <article
        v-for="pkg in packages"
        :key="pkg.id"
        class="group relative flex flex-col gap-3 p-5 rounded-xl border bg-n-solid-1 transition-all duration-200 motion-safe:hover:-translate-y-0.5 motion-safe:hover:shadow-xl"
        :class="
          pkg.badge === 'popular'
            ? 'border-n-teal-9/60 ring-1 ring-n-teal-9/40 shadow-md shadow-n-teal-9/10'
            : 'border-n-weak'
        "
      >
        <span
          v-if="badgeMeta(pkg.badge)"
          class="absolute -top-2.5 left-1/2 -translate-x-1/2 inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-[0.14em] shadow-md"
          :class="badgeMeta(pkg.badge).cls"
        >
          <Icon :icon="badgeMeta(pkg.badge).icon" class="size-3" />
          {{ badgeMeta(pkg.badge).label }}
        </span>

        <header class="flex items-baseline gap-1">
          <span
            class="text-[28px] font-bold text-n-slate-12 leading-none tracking-tight tabular-nums"
          >
            {{ formatBrlShort(pkg.amount_cents_brl) }}
          </span>
        </header>

        <p
          v-if="pkg.bonus_cents_brl > 0"
          class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-n-teal-3/60 text-n-teal-12 text-[11px] font-semibold w-fit m-0"
        >
          <Icon icon="i-lucide-gift" class="size-3" />
          {{
            t('ATHENAS_CREDITS.MODAL.CARD.BONUS', {
              bonus: formatBrlShort(pkg.bonus_cents_brl),
            })
          }}
        </p>
        <p v-else class="text-[11px] font-medium text-n-slate-10 m-0">
          {{ t('ATHENAS_CREDITS.MODAL.CARD.NO_BONUS') }}
        </p>

        <p class="text-[12px] text-n-slate-11 m-0">
          {{
            t('ATHENAS_CREDITS.BILLING.CREDITS_AS', {
              credits: formatBrlPrecise(pkg.credit_cents_brl),
            })
          }}
        </p>

        <button
          type="button"
          class="mt-2 inline-flex items-center justify-center gap-1.5 px-3 h-9 rounded-lg text-[12px] font-semibold transition-all duration-200 cursor-pointer shadow-md shadow-n-teal-9/30 hover:shadow-lg hover:shadow-n-teal-9/40 motion-safe:active:scale-[0.98]"
          :class="
            pkg.badge === 'popular'
              ? 'bg-gradient-to-br from-n-teal-9 to-n-teal-10 hover:from-n-teal-10 hover:to-n-teal-9 text-white'
              : 'bg-n-solid-2 hover:bg-gradient-to-br hover:from-n-teal-9 hover:to-n-teal-10 hover:text-white text-n-slate-12'
          "
          @click="onCheckout(pkg)"
        >
          {{ t('ATHENAS_CREDITS.MODAL.CARD.CTA') }}
          <Icon icon="i-lucide-arrow-right" class="size-3.5" />
        </button>
      </article>
    </div>
  </section>
</template>
