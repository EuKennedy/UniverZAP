<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Icon from 'next/icon/Icon.vue';

// One order of the customer's store history: a compact line (number, date,
// items, status, total) that opens into the order summary, with buttons to
// walk to the newer and the older order without leaving the card.
const props = defineProps({
  order: { type: Object, required: true },
  open: { type: Boolean, default: false },
  position: { type: Number, required: true },
  total: { type: Number, required: true },
  hasNewer: { type: Boolean, default: false },
  hasOlder: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle', 'newer', 'older']);

const { t, te, locale } = useI18n();

// Same palette as the salon's agenda: waiting in amber, under way in teal,
// done in neutral (like "Atendida"), lost in ruby.
const STATUS_CLASSES = {
  pending: 'bg-n-amber-5 text-n-amber-12',
  'on-hold': 'bg-n-amber-5 text-n-amber-12',
  processing: 'bg-n-teal-5 text-n-teal-12',
  completed: 'bg-n-slate-4 text-n-slate-12',
  failed: 'bg-n-ruby-5 text-n-ruby-12',
  cancelled: 'bg-n-ruby-5 text-n-ruby-12',
  refunded: 'bg-n-ruby-3 text-n-ruby-11',
};

// Product photos come from the store; a broken one falls back to the icon.
const brokenImages = ref(new Set());

const intlLocale = computed(() => locale.value.replace('_', '-'));
const money = value =>
  new Intl.NumberFormat(intlLocale.value, {
    style: 'currency',
    currency: props.order.currency || 'BRL',
  }).format(Number(value) || 0);
const formatDate = (value, options) => {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? '—'
    : date.toLocaleDateString(intlLocale.value, options);
};

const placed = computed(() =>
  formatDate(props.order.placed_at, {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
);
const paid = computed(() =>
  props.order.paid_at
    ? formatDate(props.order.paid_at, {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      })
    : ''
);
const items = computed(() => props.order.items || []);
const itemsCount = computed(() =>
  items.value.reduce((sum, item) => sum + (Number(item.quantity) || 0), 0)
);
const paidOn = computed(() =>
  paid.value ? t('STORE_ORDERS.PAID_ON', { date: paid.value }) : ''
);

const statusLabel = computed(() => {
  const key = `STORE_ORDERS.STATUS.${props.order.status.replace('-', '_').toUpperCase()}`;
  return te(key) ? t(key) : props.order.status;
});
const statusClass = computed(
  () => STATUS_CLASSES[props.order.status] || 'bg-n-slate-3 text-n-slate-12'
);
const panelId = computed(() => `store-order-${props.order.id}`);

const copyTracking = async () => {
  await copyTextToClipboard(props.order.tracking.code);
  useAlert(t('STORE_ORDERS.TRACKING_COPIED'));
};
</script>

<template>
  <li :data-order-id="order.id" data-testid="store-order">
    <button
      type="button"
      class="flex items-start w-full gap-2 px-3 py-2.5 text-left transition-colors hover:bg-n-alpha-1"
      :class="{ 'bg-n-alpha-1': open }"
      :aria-expanded="open"
      :aria-controls="panelId"
      data-testid="store-order-toggle"
      @click="emit('toggle')"
    >
      <Icon
        icon="i-lucide-chevron-right"
        class="mt-0.5 size-4 shrink-0 text-n-slate-10 transition-transform duration-200"
        :class="{ 'rotate-90': open }"
      />
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span class="flex items-center justify-between gap-2">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ t('STORE_ORDERS.ORDER_NUMBER', { number: order.number }) }}
          </span>
          <span class="text-sm font-semibold tabular-nums text-n-slate-12">
            {{ money(order.total) }}
          </span>
        </span>
        <span class="flex items-center justify-between gap-2">
          <span class="text-xs truncate text-n-slate-11">
            {{ placed }} · {{ t('STORE_ORDERS.ITEMS', itemsCount) }}
          </span>
          <span
            class="shrink-0 px-1.5 py-0.5 rounded text-xxs font-medium"
            :class="statusClass"
          >
            {{ statusLabel }}
          </span>
        </span>
      </span>
    </button>

    <!-- Rows of 0fr/1fr let the summary slide open and shut without
         measuring heights; closed, it stays out of the tab order (inert). -->
    <div
      :id="panelId"
      class="grid transition-[grid-template-rows] duration-200 ease-out"
      :class="open ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'"
      :inert="!open || undefined"
    >
      <div class="overflow-hidden">
        <div
          class="flex flex-col gap-3 pt-1 pb-3 pl-9 pr-3 bg-n-alpha-1"
          data-testid="store-order-summary"
        >
          <ul class="flex flex-col gap-2 m-0 list-none">
            <li
              v-for="(item, index) in items"
              :key="index"
              class="flex items-center gap-2"
            >
              <img
                v-if="item.image && !brokenImages.has(item.image)"
                :src="item.image"
                alt=""
                class="object-cover rounded-md size-8 shrink-0 bg-n-alpha-2"
                @error="brokenImages = new Set([...brokenImages, item.image])"
              />
              <span
                v-else
                class="grid rounded-md size-8 shrink-0 place-content-center bg-n-alpha-2"
              >
                <Icon icon="i-lucide-package" class="size-4 text-n-slate-10" />
              </span>
              <span class="flex-1 min-w-0 text-xs text-n-slate-12 line-clamp-2">
                {{
                  t('STORE_ORDERS.ITEM', {
                    quantity: item.quantity,
                    name: item.name,
                  })
                }}
              </span>
              <span class="text-xs tabular-nums text-n-slate-11">
                {{ money(item.total) }}
              </span>
            </li>
          </ul>

          <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 m-0 text-xs">
            <template v-if="order.payment_method_title || paidOn">
              <dt class="text-n-slate-11">{{ t('STORE_ORDERS.PAYMENT') }}</dt>
              <dd class="m-0 text-right text-n-slate-12">
                {{ order.payment_method_title }}
                <span v-if="paidOn" class="block text-n-slate-10">
                  {{ paidOn }}
                </span>
              </dd>
            </template>
            <template v-if="order.tracking?.code">
              <dt class="text-n-slate-11">{{ t('STORE_ORDERS.TRACKING') }}</dt>
              <dd class="m-0 text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 font-mono text-n-slate-12 hover:underline"
                  :title="t('STORE_ORDERS.COPY_TRACKING')"
                  @click="copyTracking"
                >
                  {{ order.tracking.code }}
                  <Icon icon="i-lucide-copy" class="size-3 text-n-slate-10" />
                </button>
                <span
                  v-if="order.tracking.carrier"
                  class="block text-n-slate-10"
                >
                  {{ order.tracking.carrier }}
                </span>
              </dd>
            </template>
          </dl>
          <div
            class="flex items-baseline justify-between gap-3 pt-2 border-t border-n-weak"
          >
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('STORE_ORDERS.TOTAL') }}
            </span>
            <span class="text-sm font-semibold tabular-nums text-n-slate-12">
              {{ money(order.total) }}
            </span>
          </div>

          <div class="flex flex-wrap items-center gap-3 text-xs">
            <a
              v-if="order.payment_url && order.status === 'pending'"
              :href="order.payment_url"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 text-n-teal-11 hover:underline"
            >
              <Icon icon="i-lucide-credit-card" class="size-3.5" />
              {{ t('STORE_ORDERS.PAYMENT_LINK') }}
            </a>
            <a
              :href="order.admin_url"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-slate-12 hover:underline"
            >
              <Icon icon="i-lucide-external-link" class="size-3.5" />
              {{ t('STORE_ORDERS.OPEN_IN_STORE') }}
            </a>
          </div>

          <nav
            class="flex items-center justify-between gap-2 pt-2 border-t border-n-weak"
            :aria-label="t('STORE_ORDERS.NAVIGATION')"
          >
            <button
              type="button"
              class="inline-flex items-center gap-0.5 text-xs text-n-slate-11 hover:text-n-slate-12 disabled:opacity-40 disabled:pointer-events-none"
              :disabled="!hasNewer"
              data-testid="store-order-newer"
              @click="emit('newer')"
            >
              <Icon icon="i-lucide-chevron-left" class="size-3.5" />
              {{ t('STORE_ORDERS.NEWER') }}
            </button>
            <span class="text-xxs tabular-nums text-n-slate-10">
              {{ t('STORE_ORDERS.POSITION', { current: position, total }) }}
            </span>
            <button
              type="button"
              class="inline-flex items-center gap-0.5 text-xs text-n-slate-11 hover:text-n-slate-12 disabled:opacity-40 disabled:pointer-events-none"
              :disabled="!hasOlder"
              data-testid="store-order-older"
              @click="emit('older')"
            >
              {{ t('STORE_ORDERS.OLDER') }}
              <Icon icon="i-lucide-chevron-right" class="size-3.5" />
            </button>
          </nav>
        </div>
      </div>
    </div>
  </li>
</template>
