<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// One order in the customer's store history, laid out like the salon's
// appointment rows: the date and the status on top, the order and its value
// below.
const props = defineProps({
  order: { type: Object, required: true },
  emphasis: { type: Boolean, default: false },
});

const { t, te, locale } = useI18n();

const STATUS_CLASSES = {
  pending: 'bg-n-amber-5 text-n-amber-12',
  'on-hold': 'bg-n-amber-5 text-n-amber-12',
  processing: 'bg-n-teal-5 text-n-teal-12',
  completed: 'bg-n-blue-5 text-n-blue-12',
  failed: 'bg-n-ruby-5 text-n-ruby-12',
  cancelled: 'bg-n-ruby-5 text-n-ruby-12',
  refunded: 'bg-n-slate-3 text-n-slate-12',
};

const intlLocale = computed(() => locale.value.replace('_', '-'));

const when = computed(() => {
  const date = new Date(props.order.placed_at);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleDateString(intlLocale.value, {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
});

const total = computed(() =>
  new Intl.NumberFormat(intlLocale.value, {
    style: 'currency',
    currency: props.order.currency || 'BRL',
  }).format(Number(props.order.total) || 0)
);

const statusLabel = computed(() => {
  const key = `STORE_ORDERS.STATUS.${props.order.status.replace('-', '_').toUpperCase()}`;
  return te(key) ? t(key) : props.order.status;
});
const statusClass = computed(
  () => STATUS_CLASSES[props.order.status] || 'bg-n-slate-3 text-n-slate-12'
);
</script>

<template>
  <div class="flex flex-col gap-0.5 py-2" data-testid="store-order-row">
    <div class="flex items-start justify-between gap-2">
      <span
        class="text-n-slate-12"
        :class="emphasis ? 'text-base font-semibold' : 'text-sm font-medium'"
      >
        {{ when }}
      </span>
      <span class="text-xs px-2 py-0.5 rounded shrink-0" :class="statusClass">
        {{ statusLabel }}
      </span>
    </div>
    <div class="text-sm text-n-slate-11 truncate">
      <a
        :href="order.admin_url"
        target="_blank"
        rel="noopener noreferrer"
        class="hover:underline hover:text-n-slate-12"
      >
        {{ t('STORE_ORDERS.ORDER_NUMBER', { number: order.number }) }}
      </a>
      <span class="text-n-slate-12"> · {{ total }}</span>
      <span v-if="order.payment_method_title">
        · {{ order.payment_method_title }}
      </span>
    </div>
  </div>
</template>
