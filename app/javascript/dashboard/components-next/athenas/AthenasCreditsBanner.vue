<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';
import Icon from 'next/icon/Icon.vue';

// Soft warnings before the hard paywall hits. Threshold transitions
// (80% used → yellow, 95% → orange, exhausted → red) come straight
// from the backend so the banner state can never disagree with the
// gate. Each variant gets its own copy + colour scheme + CTA emphasis.
const { t } = useI18n();
const { showBanner, status, balanceBrl, percentRemaining, openTopUpModal } =
  useAthenasCredits();

const variant = computed(() => {
  if (status.value === 'exhausted') {
    return {
      ring: 'border-n-ruby-7/60 bg-n-ruby-3/30',
      icon: 'i-lucide-alert-octagon',
      iconCls: 'text-n-ruby-11',
      title: t('ATHENAS_CREDITS.BANNER.EXHAUSTED.TITLE'),
      body: t('ATHENAS_CREDITS.BANNER.EXHAUSTED.BODY'),
      ctaCls: 'bg-gradient-to-br from-n-ruby-9 to-n-ruby-10 text-white',
    };
  }
  if (status.value === 'warn_95') {
    return {
      ring: 'border-n-amber-7/60 bg-n-amber-3/30',
      icon: 'i-lucide-alert-triangle',
      iconCls: 'text-n-amber-11 motion-safe:animate-pulse',
      title: t('ATHENAS_CREDITS.BANNER.WARN_95.TITLE'),
      body: t('ATHENAS_CREDITS.BANNER.WARN_95.BODY', {
        balance: balanceBrl.value,
        percent: percentRemaining.value,
      }),
      ctaCls: 'bg-gradient-to-br from-n-amber-9 to-n-amber-10 text-white',
    };
  }
  return {
    ring: 'border-n-amber-7/40 bg-n-amber-3/15',
    icon: 'i-lucide-info',
    iconCls: 'text-n-amber-11',
    title: t('ATHENAS_CREDITS.BANNER.WARN_80.TITLE'),
    body: t('ATHENAS_CREDITS.BANNER.WARN_80.BODY', {
      balance: balanceBrl.value,
      percent: percentRemaining.value,
    }),
    ctaCls: 'bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white',
  };
});
</script>

<template>
  <Transition
    enter-active-class="motion-safe:transition-all motion-safe:duration-400 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)]"
    enter-from-class="opacity-0 -translate-y-2"
    enter-to-class="opacity-100 translate-y-0"
    leave-active-class="motion-safe:transition-all motion-safe:duration-200 motion-safe:ease-in"
    leave-from-class="opacity-100"
    leave-to-class="opacity-0 -translate-y-2"
  >
    <div
      v-if="showBanner"
      class="sticky top-0 z-40 mx-3 mt-3 border rounded-2xl backdrop-blur-xl shadow-md px-4 py-3 flex items-center gap-3"
      :class="variant.ring"
      role="status"
    >
      <span
        class="inline-flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 flex-shrink-0"
      >
        <Icon :icon="variant.icon" class="size-5" :class="variant.iconCls" />
      </span>
      <div class="flex flex-col gap-0.5 flex-1 min-w-0">
        <p class="text-[13px] font-semibold text-n-slate-12 m-0 leading-tight">
          {{ variant.title }}
        </p>
        <p class="text-[12px] text-n-slate-11 m-0 leading-snug">
          {{ variant.body }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-[12px] font-semibold shadow-md cursor-pointer transition-all motion-safe:hover:shadow-lg motion-safe:active:scale-[0.97] flex-shrink-0"
        :class="variant.ctaCls"
        @click="openTopUpModal('banner_cta')"
      >
        <Icon icon="i-lucide-credit-card" class="size-3.5" />
        {{ $t('ATHENAS_CREDITS.BANNER.CTA') }}
      </button>
    </div>
  </Transition>
</template>
