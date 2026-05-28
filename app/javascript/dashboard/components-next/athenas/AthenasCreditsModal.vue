<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';
import Icon from 'next/icon/Icon.vue';

// Stripe / Hotmart-grade paywall modal. Renders three packages with the
// middle card carrying the "popular" anchor; the right one shows "melhor
// valor" with the highest bonus ratio. Glass-morph backdrop, brand-teal
// gradient, dopamine-green CTAs, staggered card entry. Opens itself
// whenever an axios 402 (`athenas_quota_exhausted`) lands or the user
// hits the launcher manually.
const { t } = useI18n();
const {
  packages,
  pricing,
  status,
  isExhausted,
  balanceCents,
  balanceBrl,
  burnRatePerDay,
  daysRemaining,
  TOP_UP_EVENT,
  refresh,
} = useAthenasCredits();

const isOpen = ref(false);
const reason = ref('manual');
const entered = ref(false);
let enterTimeout = null;

const open = ({ reason: openReason = 'manual' } = {}) => {
  isOpen.value = true;
  reason.value = openReason;
  entered.value = false;
  // Two-frame defer so the CSS transitions catch the from→to delta
  // instead of snapping straight into the rest state.
  requestAnimationFrame(() => {
    enterTimeout = window.setTimeout(() => {
      entered.value = true;
    }, 30);
  });
  refresh({ force: true });
};

const close = () => {
  entered.value = false;
  window.setTimeout(() => {
    isOpen.value = false;
  }, 220);
};

const onKey = event => {
  if (!isOpen.value) return;
  if (event.key === 'Escape') close();
};

onMounted(() => {
  emitter.on(TOP_UP_EVENT, open);
  document.addEventListener('keydown', onKey);
});

onBeforeUnmount(() => {
  emitter.off(TOP_UP_EVENT, open);
  document.removeEventListener('keydown', onKey);
  if (enterTimeout) window.clearTimeout(enterTimeout);
});

// Pre-compute display strings per card. We resolve everything client-side
// from the catalogue payload so the UI keeps rendering even if the
// pricing/burn-rate API is briefly missing.
const formatBrl = cents => `R$ ${(cents / 100).toFixed(2).replace('.', ',')}`;
const formatBrlShort = cents => `R$ ${Math.round(cents / 100)}`;

const conversationsForPackage = pkg => {
  if (!pricing.value) return null;
  const sonnet = pricing.value.sonnet_cents_per_conversation || 1;
  const haiku = pricing.value.haiku_cents_per_conversation || 1;
  return {
    sonnet: Math.floor((pkg.credit_cents_brl / sonnet) * 10) / 10,
    haiku: Math.floor((pkg.credit_cents_brl / haiku) * 10) / 10,
  };
};

const daysForPackage = pkg => {
  const rate = burnRatePerDay.value;
  if (!rate || rate <= 0) return null;
  return Math.floor(pkg.credit_cents_brl / rate);
};

const onCheckout = pkg => {
  // Pre-prime the meter so when the operator returns from Univercart
  // the dashboard is already polling and picks up the credit fast.
  refresh({ force: true });
  window.open(pkg.checkout_url, '_blank', 'noopener,noreferrer');
};

const headerCopy = computed(() => {
  if (isExhausted.value || reason.value === 'quota_exhausted') {
    return {
      eyebrow: t('ATHENAS_CREDITS.MODAL.EYEBROW_EXHAUSTED'),
      title: t('ATHENAS_CREDITS.MODAL.TITLE_EXHAUSTED'),
      subtitle: t('ATHENAS_CREDITS.MODAL.SUBTITLE_EXHAUSTED'),
    };
  }
  if (status.value === 'warn_95' || status.value === 'warn_80') {
    return {
      eyebrow: t('ATHENAS_CREDITS.MODAL.EYEBROW_WARN'),
      title: t('ATHENAS_CREDITS.MODAL.TITLE_WARN'),
      subtitle: t('ATHENAS_CREDITS.MODAL.SUBTITLE_WARN', {
        balance: balanceBrl.value,
      }),
    };
  }
  return {
    eyebrow: t('ATHENAS_CREDITS.MODAL.EYEBROW_MANUAL'),
    title: t('ATHENAS_CREDITS.MODAL.TITLE_MANUAL'),
    subtitle: t('ATHENAS_CREDITS.MODAL.SUBTITLE_MANUAL', {
      balance: balanceBrl.value,
    }),
  };
});

const badgeMeta = badge => {
  if (badge === 'popular') {
    return {
      label: t('ATHENAS_CREDITS.MODAL.BADGE.POPULAR'),
      cls: 'bg-gradient-to-r from-n-teal-9 to-n-teal-10 text-white',
    };
  }
  if (badge === 'best_value') {
    return {
      label: t('ATHENAS_CREDITS.MODAL.BADGE.BEST_VALUE'),
      cls: 'bg-gradient-to-r from-n-amber-9 to-n-amber-10 text-white',
    };
  }
  return null;
};
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="motion-safe:transition-opacity motion-safe:duration-300"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="motion-safe:transition-opacity motion-safe:duration-200"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isOpen"
        class="fixed inset-0 z-[9995] flex items-center justify-center p-6 bg-black/90 backdrop-blur-xl"
        role="dialog"
        aria-modal="true"
        :aria-label="headerCopy.title"
        @mousedown.self="close"
      >
        <div
          class="relative w-full max-w-5xl rounded-3xl bg-n-surface-1/95 backdrop-blur-2xl border border-n-teal-7/40 shadow-[0_40px_120px_-20px_rgba(0,0,0,0.7)] overflow-hidden motion-safe:transition-all motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
          :class="
            entered
              ? 'opacity-100 translate-y-0 scale-100'
              : 'opacity-0 translate-y-6 scale-[0.97]'
          "
        >
          <span
            class="absolute -top-32 -right-24 size-80 rounded-full bg-n-teal-9/20 blur-3xl pointer-events-none"
            aria-hidden="true"
          />
          <span
            class="absolute -bottom-32 -left-24 size-80 rounded-full bg-n-iris-9/15 blur-3xl pointer-events-none"
            aria-hidden="true"
          />
          <div
            class="absolute inset-x-0 top-0 h-[3px] bg-gradient-to-r from-n-teal-9 via-n-teal-10 to-n-teal-9"
          />

          <!-- HEADER -->
          <header
            class="relative px-10 pt-10 pb-6 flex items-start justify-between gap-6"
          >
            <div class="flex items-start gap-4 min-w-0">
              <span
                class="inline-flex items-center justify-center size-14 rounded-2xl bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-xl shadow-n-teal-9/30 ring-1 ring-white/10 flex-shrink-0"
              >
                <Icon icon="i-lucide-sparkles" class="size-7" />
              </span>
              <div class="flex flex-col gap-1 min-w-0">
                <p
                  class="text-[11px] font-bold uppercase tracking-[0.2em] text-n-teal-11 m-0"
                >
                  {{ headerCopy.eyebrow }}
                </p>
                <h2
                  class="text-2xl font-semibold text-n-slate-12 m-0 leading-tight tracking-tight"
                >
                  {{ headerCopy.title }}
                </h2>
                <p
                  class="text-sm text-n-slate-11 m-0 mt-1 leading-relaxed max-w-2xl"
                >
                  {{ headerCopy.subtitle }}
                </p>
              </div>
            </div>
            <button
              type="button"
              class="size-9 rounded-lg flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition cursor-pointer flex-shrink-0"
              :aria-label="t('ATHENAS_CREDITS.MODAL.CLOSE')"
              @click="close"
            >
              <Icon icon="i-lucide-x" class="size-5" />
            </button>
          </header>

          <!-- META STRIP -->
          <div
            class="relative grid grid-cols-3 gap-4 px-10 py-5 border-y border-n-weak/40 bg-n-alpha-1/40"
          >
            <div class="flex flex-col gap-0.5 min-w-0">
              <p
                class="text-[10px] font-bold uppercase tracking-[0.15em] text-n-slate-10 m-0"
              >
                {{ t('ATHENAS_CREDITS.MODAL.META.BALANCE') }}
              </p>
              <p class="text-lg font-semibold text-n-slate-12 m-0 tabular-nums">
                {{ formatBrl(balanceCents) }}
              </p>
            </div>
            <div class="flex flex-col gap-0.5 min-w-0">
              <p
                class="text-[10px] font-bold uppercase tracking-[0.15em] text-n-slate-10 m-0"
              >
                {{ t('ATHENAS_CREDITS.MODAL.META.BURN_RATE') }}
              </p>
              <p class="text-lg font-semibold text-n-slate-12 m-0 tabular-nums">
                {{ `${formatBrl(burnRatePerDay)}/d` }}
              </p>
            </div>
            <div class="flex flex-col gap-0.5 min-w-0">
              <p
                class="text-[10px] font-bold uppercase tracking-[0.15em] text-n-slate-10 m-0"
              >
                {{ t('ATHENAS_CREDITS.MODAL.META.DAYS_REMAINING') }}
              </p>
              <p class="text-lg font-semibold text-n-slate-12 m-0 tabular-nums">
                <template
                  v-if="daysRemaining !== null && daysRemaining !== undefined"
                >
                  {{ daysRemaining }} {{ t('ATHENAS_CREDITS.MODAL.META.DAYS') }}
                </template>
                <template v-else>—</template>
              </p>
            </div>
          </div>

          <!-- CARDS -->
          <section
            class="relative px-10 py-8 grid grid-cols-1 md:grid-cols-3 gap-5"
          >
            <article
              v-for="(pkg, idx) in packages"
              :key="pkg.id"
              class="group relative flex flex-col gap-4 p-6 rounded-2xl border bg-n-solid-1 transition-all duration-300 motion-safe:hover:-translate-y-1 motion-safe:hover:shadow-2xl"
              :class="[
                pkg.badge === 'popular'
                  ? 'border-n-teal-9/60 ring-2 ring-n-teal-9/40 shadow-xl shadow-n-teal-9/10 motion-safe:scale-[1.02]'
                  : 'border-n-weak',
                entered
                  ? 'opacity-100 translate-y-0'
                  : 'opacity-0 translate-y-3',
              ]"
              :style="{
                transitionDelay: entered ? `${100 + idx * 80}ms` : '0ms',
              }"
            >
              <span
                v-if="badgeMeta(pkg.badge)"
                class="absolute -top-3 left-1/2 -translate-x-1/2 inline-flex items-center gap-1 px-3 py-1 rounded-full text-[10px] font-bold uppercase tracking-[0.15em] shadow-md"
                :class="badgeMeta(pkg.badge).cls"
              >
                <Icon
                  :icon="
                    pkg.badge === 'popular' ? 'i-lucide-zap' : 'i-lucide-crown'
                  "
                  class="size-3"
                />
                {{ badgeMeta(pkg.badge).label }}
              </span>

              <header class="flex items-baseline gap-1">
                <span
                  class="text-[36px] font-bold text-n-slate-12 m-0 leading-none tracking-tight tabular-nums"
                >
                  {{ formatBrlShort(pkg.amount_cents_brl) }}
                </span>
                <span class="text-sm text-n-slate-10 m-0">
                  {{ t('ATHENAS_CREDITS.MODAL.CARD.ONE_TIME') }}
                </span>
              </header>

              <div
                v-if="pkg.bonus_cents_brl > 0"
                class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-n-teal-3/60 text-n-teal-12 text-[11px] font-semibold w-fit"
              >
                <Icon icon="i-lucide-gift" class="size-3" />
                {{
                  t('ATHENAS_CREDITS.MODAL.CARD.BONUS', {
                    bonus: formatBrlShort(pkg.bonus_cents_brl),
                  })
                }}
              </div>
              <p v-else class="text-[11px] font-medium text-n-slate-10 m-0">
                {{ t('ATHENAS_CREDITS.MODAL.CARD.NO_BONUS') }}
              </p>

              <ul class="flex flex-col gap-2 m-0 p-0 list-none mt-1">
                <li class="flex items-start gap-2 text-[13px] text-n-slate-11">
                  <Icon
                    icon="i-lucide-message-circle"
                    class="size-4 text-n-teal-11 mt-0.5 flex-shrink-0"
                  />
                  <span>
                    <strong class="text-n-slate-12 tabular-nums">
                      {{
                        `~${Math.round((conversationsForPackage(pkg) || {}).sonnet || 0)}`
                      }}
                    </strong>
                    {{ t('ATHENAS_CREDITS.MODAL.CARD.CONVERSATIONS_SONNET') }}
                  </span>
                </li>
                <li class="flex items-start gap-2 text-[13px] text-n-slate-11">
                  <Icon
                    icon="i-lucide-message-square"
                    class="size-4 text-n-teal-11 mt-0.5 flex-shrink-0"
                  />
                  <span>
                    <strong class="text-n-slate-12 tabular-nums">
                      {{
                        `~${Math.round((conversationsForPackage(pkg) || {}).haiku || 0)}`
                      }}
                    </strong>
                    {{ t('ATHENAS_CREDITS.MODAL.CARD.CONVERSATIONS_HAIKU') }}
                  </span>
                </li>
                <li
                  v-if="daysForPackage(pkg)"
                  class="flex items-start gap-2 text-[13px] text-n-slate-11"
                >
                  <Icon
                    icon="i-lucide-calendar-days"
                    class="size-4 text-n-teal-11 mt-0.5 flex-shrink-0"
                  />
                  <span>
                    <strong class="text-n-slate-12 tabular-nums">
                      {{ `~${daysForPackage(pkg)}` }}
                    </strong>
                    {{ t('ATHENAS_CREDITS.MODAL.CARD.DAYS') }}
                  </span>
                </li>
                <li class="flex items-start gap-2 text-[13px] text-n-slate-11">
                  <Icon
                    icon="i-lucide-infinity"
                    class="size-4 text-n-teal-11 mt-0.5 flex-shrink-0"
                  />
                  <span>{{
                    t('ATHENAS_CREDITS.MODAL.CARD.NEVER_EXPIRES')
                  }}</span>
                </li>
              </ul>

              <button
                type="button"
                class="mt-auto inline-flex items-center justify-center gap-2 px-4 h-11 rounded-xl text-sm font-semibold transition-all duration-200 cursor-pointer shadow-lg shadow-n-teal-9/30 hover:shadow-xl hover:shadow-n-teal-9/40 motion-safe:active:scale-[0.98]"
                :class="
                  pkg.badge === 'popular'
                    ? 'bg-gradient-to-br from-n-teal-9 to-n-teal-10 hover:from-n-teal-10 hover:to-n-teal-9 text-white'
                    : 'bg-n-solid-2 hover:bg-gradient-to-br hover:from-n-teal-9 hover:to-n-teal-10 hover:text-white text-n-slate-12'
                "
                @click="onCheckout(pkg)"
              >
                {{ t('ATHENAS_CREDITS.MODAL.CARD.CTA') }}
                <Icon
                  icon="i-lucide-arrow-right"
                  class="size-4 group-hover:translate-x-0.5 transition-transform"
                />
              </button>
            </article>
          </section>

          <!-- FOOTER -->
          <footer
            class="relative px-10 py-5 border-t border-n-weak/40 bg-n-alpha-1/30 flex items-center justify-between gap-4 flex-wrap"
          >
            <p
              class="text-[11px] text-n-slate-10 m-0 inline-flex items-center gap-1.5"
            >
              <Icon
                icon="i-lucide-shield-check"
                class="size-3.5 text-n-teal-11"
              />
              {{ t('ATHENAS_CREDITS.MODAL.FOOTER.TRUST') }}
            </p>
            <p class="text-[11px] text-n-slate-10 m-0">
              {{ t('ATHENAS_CREDITS.MODAL.FOOTER.AUTO_CREDIT') }}
            </p>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
