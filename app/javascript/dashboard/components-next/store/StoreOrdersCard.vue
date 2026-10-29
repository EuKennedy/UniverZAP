<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'next/icon/Icon.vue';
import StoreOrderRow from './StoreOrderRow.vue';

// The customer's orders from the workspace's store, under the sheet and in the
// same shape as the salon's agenda: who she is in the store, what she spent,
// the order she is still waiting for and her whole history, newest first.
// Everything comes from the orders already imported here: opening a
// conversation never asks the store.
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t, locale } = useI18n();

// Unpaid, on hold, or paid and not shipped yet.
const IN_PROGRESS = ['pending', 'on-hold', 'processing'];

const data = ref(null);
const orders = ref([]);
const page = ref(1);
const isLoading = ref(false);
const isLoadingMore = ref(false);
// Product photos come from the store; a broken one falls back to the icon.
const brokenImages = ref(new Set());

const storeName = computed(
  () => data.value?.store_name || t('STORE_ORDERS.STORE')
);
const customer = computed(() => data.value?.customer || {});
const customerName = computed(
  () => customer.value.customer_name || customer.value.customer_email || ''
);
const metrics = computed(() => data.value?.metrics || {});
const recurring = computed(() => (metrics.value.orders_count ?? 0) > 1);
// Only the newest order can be "on its way": an old unpaid one was abandoned.
const current = computed(() =>
  IN_PROGRESS.includes(orders.value[0]?.status) ? orders.value[0] : null
);
const history = computed(() =>
  current.value ? orders.value.slice(1) : orders.value
);

const intlLocale = computed(() => locale.value.replace('_', '-'));
const money = (value, currency = 'BRL') =>
  new Intl.NumberFormat(intlLocale.value, {
    style: 'currency',
    currency,
  }).format(Number(value) || 0);
const day = value =>
  value
    ? new Date(value).toLocaleDateString(intlLocale.value, {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      })
    : '—';

const tiles = computed(() => [
  {
    key: 'orders',
    label: t('STORE_ORDERS.ORDERS'),
    value: String(metrics.value.orders_count ?? 0),
  },
  {
    key: 'spent',
    label: t('STORE_ORDERS.SPENT'),
    value: money(metrics.value.total_spent),
  },
  {
    key: 'ticket',
    label: t('STORE_ORDERS.TICKET'),
    value: money(metrics.value.average_ticket),
  },
  {
    key: 'last',
    label: t('STORE_ORDERS.LAST'),
    value: day(metrics.value.last_order_at),
  },
]);

const fetchPage = async number => {
  const { data: body } = await WoocommerceAPI.getOrders(
    props.contactId,
    number
  );
  return body;
};

const load = async () => {
  isLoading.value = true;
  page.value = 1;
  try {
    data.value = await fetchPage(1);
    orders.value = data.value.orders || [];
  } catch {
    data.value = null;
    orders.value = [];
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  isLoadingMore.value = true;
  try {
    const body = await fetchPage(page.value + 1);
    page.value += 1;
    orders.value = [...orders.value, ...(body.orders || [])];
    data.value = { ...data.value, has_more: body.has_more };
  } finally {
    isLoadingMore.value = false;
  }
};

const copyTracking = async code => {
  await copyTextToClipboard(code);
  useAlert(t('STORE_ORDERS.TRACKING_COPIED'));
};

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <div
    v-if="isLoading || data?.connected"
    class="pt-2 border-t border-n-weak text-sm text-n-slate-12 flex flex-col gap-2"
    data-testid="store-orders"
  >
    <p class="text-xs uppercase tracking-wide text-n-slate-11">
      {{ t('STORE_ORDERS.TITLE', { store: storeName }) }}
    </p>
    <div v-if="isLoading" class="flex justify-center items-center p-4">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <p v-else-if="!orders.length" class="text-n-slate-11">
      {{ t('STORE_ORDERS.EMPTY', { store: storeName }) }}
    </p>

    <template v-else>
      <p
        class="flex items-center gap-2 text-xs text-n-slate-11"
        :title="customer.customer_email"
      >
        <span v-if="customerName" class="truncate">
          {{
            t('STORE_ORDERS.CLIENT_AT', {
              name: customerName,
              store: storeName,
            })
          }}
        </span>
        <span
          v-if="recurring"
          class="shrink-0 px-1.5 py-0.5 rounded bg-n-amber-5 text-n-amber-12"
          data-testid="store-recurring"
        >
          {{ t('STORE_ORDERS.RECURRENT') }}
        </span>
      </p>

      <dl
        class="grid grid-cols-2 gap-x-3 gap-y-2 rounded-lg px-3 py-2 bg-n-slate-2 outline outline-1 outline-n-weak"
        data-testid="store-stats"
      >
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col min-w-0"
          :data-testid="`store-stat-${tile.key}`"
        >
          <dt class="text-xs text-n-slate-11 truncate">{{ tile.label }}</dt>
          <dd class="text-sm font-semibold truncate text-n-slate-12">
            {{ tile.value }}
          </dd>
        </div>
      </dl>

      <section
        v-if="current"
        class="flex flex-col gap-1 rounded-lg px-3 pb-2 bg-n-teal-2 outline outline-1 outline-n-teal-5"
        data-testid="store-current-order"
      >
        <p class="text-xs uppercase tracking-wide text-n-teal-11 pt-2">
          {{ t('STORE_ORDERS.IN_PROGRESS') }}
        </p>
        <StoreOrderRow :order="current" emphasis />
        <ul class="flex flex-col gap-1.5 m-0 list-none">
          <li
            v-for="(item, index) in current.items"
            :key="index"
            class="flex items-center gap-2"
          >
            <img
              v-if="item.image && !brokenImages.has(item.image)"
              :src="item.image"
              alt=""
              class="object-cover rounded-md size-7 shrink-0 bg-n-alpha-2"
              @error="brokenImages = new Set([...brokenImages, item.image])"
            />
            <span
              v-else
              class="grid rounded-md size-7 shrink-0 place-content-center bg-n-alpha-2"
            >
              <Icon icon="i-lucide-package" class="size-3.5 text-n-slate-10" />
            </span>
            <span class="flex-1 min-w-0 text-xs truncate text-n-slate-12">
              {{
                t('STORE_ORDERS.ITEM', {
                  quantity: item.quantity,
                  name: item.name,
                })
              }}
            </span>
          </li>
        </ul>
        <button
          v-if="current.tracking?.code"
          type="button"
          class="flex items-center gap-2 px-2 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2"
          :title="t('STORE_ORDERS.COPY_TRACKING')"
          @click="copyTracking(current.tracking.code)"
        >
          <Icon icon="i-lucide-truck" class="size-3.5 text-n-slate-10" />
          <span class="font-mono">{{ current.tracking.code }}</span>
          <span v-if="current.tracking.carrier" class="text-n-slate-10">
            {{
              t('STORE_ORDERS.CARRIER', { carrier: current.tracking.carrier })
            }}
          </span>
          <Icon icon="i-lucide-copy" class="ml-auto size-3.5 text-n-slate-10" />
        </button>
        <a
          v-if="current.payment_url && current.status === 'pending'"
          :href="current.payment_url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1 text-xs text-n-teal-11 hover:underline"
        >
          <Icon icon="i-lucide-credit-card" class="size-3.5" />
          {{ t('STORE_ORDERS.PAYMENT_LINK') }}
        </a>
      </section>
      <p
        v-else
        class="rounded-lg px-3 py-2 bg-n-slate-2 outline outline-1 outline-n-weak text-n-slate-11"
      >
        {{ t('STORE_ORDERS.NO_IN_PROGRESS') }}
      </p>

      <section v-if="history.length" class="flex flex-col">
        <p class="text-xs uppercase tracking-wide text-n-slate-11">
          {{ t('STORE_ORDERS.HISTORY') }}
        </p>
        <StoreOrderRow
          v-for="order in history"
          :key="order.id"
          :order="order"
          class="border-b border-n-weak last:border-b-0"
        />
        <button
          v-if="data.has_more"
          type="button"
          class="self-start py-1 text-xs text-n-slate-11 hover:text-n-slate-12 hover:underline disabled:opacity-60"
          :disabled="isLoadingMore"
          data-testid="store-load-more"
          @click="loadMore"
        >
          {{ t('STORE_ORDERS.LOAD_MORE') }}
        </button>
      </section>
    </template>
  </div>
</template>
