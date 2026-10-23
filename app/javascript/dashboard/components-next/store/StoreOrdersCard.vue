<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import Icon from 'next/icon/Icon.vue';

// The customer's orders from the workspace's store, under the sheet: what she
// spent and the last order with items, payment and tracking.
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t, locale } = useI18n();

const STATUS_TONES = {
  pending: 'bg-n-amber-3 text-n-amber-11',
  'on-hold': 'bg-n-amber-3 text-n-amber-11',
  processing: 'bg-n-teal-3 text-n-teal-11',
  completed: 'bg-n-iris-3 text-n-iris-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
  cancelled: 'bg-n-slate-3 text-n-slate-11',
  refunded: 'bg-n-slate-3 text-n-slate-11',
};

const STATUS_LABELS = computed(() => ({
  pending: t('STORE_ORDERS.STATUS.PENDING'),
  'on-hold': t('STORE_ORDERS.STATUS.ON_HOLD'),
  processing: t('STORE_ORDERS.STATUS.PROCESSING'),
  completed: t('STORE_ORDERS.STATUS.COMPLETED'),
  failed: t('STORE_ORDERS.STATUS.FAILED'),
  cancelled: t('STORE_ORDERS.STATUS.CANCELLED'),
  refunded: t('STORE_ORDERS.STATUS.REFUNDED'),
}));

const data = ref(null);
// Product photos come from the store; a broken one falls back to the icon.
const brokenImages = ref(new Set());
const isLoading = ref(false);

const orders = computed(() => data.value?.orders || []);
const latest = computed(() => orders.value[0]);
const previous = computed(() => orders.value.slice(1));
const metrics = computed(() => data.value?.metrics || {});

const intlLocale = computed(() => locale.value.replace('_', '-'));
const money = (value, currency = 'BRL') =>
  new Intl.NumberFormat(intlLocale.value, {
    style: 'currency',
    currency,
  }).format(Number(value) || 0);
const date = value =>
  value
    ? new Date(value).toLocaleDateString(intlLocale.value, {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      })
    : '—';

const statusLabel = status => STATUS_LABELS.value[status] || status;
const statusTone = status =>
  STATUS_TONES[status] || 'bg-n-slate-3 text-n-slate-11';

const stats = computed(() => [
  {
    key: 'spent',
    label: t('STORE_ORDERS.SPENT'),
    value: money(metrics.value.total_spent),
  },
  {
    key: 'orders',
    label: t('STORE_ORDERS.ORDERS'),
    value: metrics.value.orders_count ?? 0,
  },
  {
    key: 'ticket',
    label: t('STORE_ORDERS.TICKET'),
    value: money(metrics.value.average_ticket),
  },
  {
    key: 'last',
    label: t('STORE_ORDERS.LAST'),
    value: date(metrics.value.last_order_at),
  },
]);

const load = async () => {
  isLoading.value = true;
  try {
    const response = await WoocommerceAPI.getOrders(props.contactId);
    data.value = response.data;
  } catch {
    data.value = null;
  } finally {
    isLoading.value = false;
  }
};

const copyTracking = async code => {
  await copyTextToClipboard(code);
  useAlert(t('STORE_ORDERS.TRACKING_COPIED'));
};

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <div>
    <section
      v-if="data?.connected"
      class="flex flex-col gap-3 pt-3 border-t border-n-weak"
      data-testid="store-orders"
    >
      <header class="flex items-center gap-2">
        <span
          class="grid rounded-md size-6 place-content-center bg-brand-gradient"
        >
          <Icon icon="i-lucide-shopping-bag" class="size-3.5 text-[#06131C]" />
        </span>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ t('STORE_ORDERS.TITLE') }}
        </h4>
      </header>

      <div class="grid grid-cols-2 gap-2">
        <div
          v-for="stat in stats"
          :key="stat.key"
          class="px-2.5 py-2 rounded-lg bg-n-alpha-1"
          :data-testid="`store-stat-${stat.key}`"
        >
          <p
            class="font-semibold tracking-wider uppercase text-xxs text-n-slate-10"
          >
            {{ stat.label }}
          </p>
          <p class="text-sm font-semibold tabular-nums text-n-slate-12">
            {{ stat.value }}
          </p>
        </div>
      </div>

      <p v-if="!latest" class="text-xs text-n-slate-10">
        {{ t('STORE_ORDERS.EMPTY') }}
      </p>

      <article
        v-else
        class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        data-testid="store-latest-order"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ t('STORE_ORDERS.ORDER_NUMBER', { number: latest.number }) }}
          </span>
          <span
            class="px-2 py-0.5 rounded-full text-xxs font-semibold"
            :class="statusTone(latest.status)"
          >
            {{ statusLabel(latest.status) }}
          </span>
        </div>
        <p class="text-xs text-n-slate-10">
          {{
            t('STORE_ORDERS.META', {
              date: date(latest.placed_at),
              method: latest.payment_method_title || '—',
            })
          }}
        </p>
        <ul class="flex flex-col gap-1.5 m-0 list-none">
          <li
            v-for="(item, index) in latest.items"
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
            <span class="flex-1 min-w-0 text-xs truncate text-n-slate-12">
              {{
                t('STORE_ORDERS.ITEM', {
                  quantity: item.quantity,
                  name: item.name,
                })
              }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              {{ money(item.total, latest.currency) }}
            </span>
          </li>
        </ul>
        <div
          class="flex items-center justify-between pt-2 border-t border-n-weak"
        >
          <span class="text-xs text-n-slate-11">{{
            t('STORE_ORDERS.TOTAL')
          }}</span>
          <span class="text-sm font-bold tabular-nums text-n-slate-12">
            {{ money(latest.total, latest.currency) }}
          </span>
        </div>
        <button
          v-if="latest.tracking?.code"
          type="button"
          class="flex items-center gap-2 px-2 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2"
          :title="t('STORE_ORDERS.COPY_TRACKING')"
          @click="copyTracking(latest.tracking.code)"
        >
          <Icon icon="i-lucide-truck" class="size-3.5 text-n-slate-10" />
          <span class="font-mono">{{ latest.tracking.code }}</span>
          <span v-if="latest.tracking.carrier" class="text-n-slate-10">
            {{
              t('STORE_ORDERS.CARRIER', { carrier: latest.tracking.carrier })
            }}
          </span>
          <Icon icon="i-lucide-copy" class="ml-auto size-3.5 text-n-slate-10" />
        </button>
        <div class="flex flex-wrap gap-3 text-xs">
          <a
            v-if="latest.payment_url && latest.status === 'pending'"
            :href="latest.payment_url"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 text-n-teal-11 hover:underline"
          >
            <Icon icon="i-lucide-credit-card" class="size-3.5" />
            {{ t('STORE_ORDERS.PAYMENT_LINK') }}
          </a>
          <a
            :href="latest.admin_url"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-slate-12 hover:underline"
          >
            <Icon icon="i-lucide-external-link" class="size-3.5" />
            {{ t('STORE_ORDERS.OPEN_IN_STORE') }}
          </a>
        </div>
      </article>

      <ul v-if="previous.length" class="flex flex-col gap-1 m-0 list-none">
        <li
          v-for="order in previous"
          :key="order.id"
          class="flex items-center gap-2 text-xs"
        >
          <a
            :href="order.admin_url"
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-n-slate-12 hover:underline"
          >
            {{ t('STORE_ORDERS.ORDER_NUMBER', { number: order.number }) }}
          </a>
          <span class="text-n-slate-10">{{ date(order.placed_at) }}</span>
          <span
            class="px-1.5 py-0.5 rounded-full text-xxs font-medium"
            :class="statusTone(order.status)"
          >
            {{ statusLabel(order.status) }}
          </span>
          <span class="ml-auto tabular-nums text-n-slate-11">
            {{ money(order.total, order.currency) }}
          </span>
        </li>
      </ul>
    </section>
  </div>
</template>
