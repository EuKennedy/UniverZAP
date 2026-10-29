<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StoreOrderItem from './StoreOrderItem.vue';

// The customer's orders from the workspace's store, under the sheet and in the
// same shape as the salon's agenda: who she is in the store, what she spent
// and her whole history, newest first. Every order starts closed; opening one
// shows its summary and lets the agent walk to the next one, loading older
// pages on the way. Everything comes from the orders already imported here:
// opening a conversation never asks the store.
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t, locale } = useI18n();

const root = ref(null);
const data = ref(null);
const orders = ref([]);
const page = ref(1);
const openId = ref(null);
const isLoading = ref(false);
const isLoadingMore = ref(false);

const storeName = computed(
  () => data.value?.store_name || t('STORE_ORDERS.STORE')
);
const customer = computed(() => data.value?.customer || {});
const customerName = computed(
  () => customer.value.customer_name || customer.value.customer_email || ''
);
const metrics = computed(() => data.value?.metrics || {});
const recurring = computed(() => (metrics.value.orders_count ?? 0) > 1);
const totalCount = computed(
  () => data.value?.total_count ?? orders.value.length
);
const hasMore = computed(() => !!data.value?.has_more);
const openIndex = computed(() =>
  orders.value.findIndex(order => order.id === openId.value)
);

const intlLocale = computed(() => locale.value.replace('_', '-'));
const money = value =>
  new Intl.NumberFormat(intlLocale.value, {
    style: 'currency',
    currency: 'BRL',
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
  openId.value = null;
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
  if (isLoadingMore.value) return;
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

const toggle = id => {
  openId.value = openId.value === id ? null : id;
};

// Walking past the last loaded order fetches the next page first.
const step = async offset => {
  const index = openIndex.value + offset;
  if (index >= orders.value.length && hasMore.value) await loadMore();
  const target = orders.value[index];
  if (!target) return;
  openId.value = target.id;
  await nextTick();
  root.value
    ?.querySelector(`[data-order-id="${target.id}"]`)
    ?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
};

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <div
    v-if="isLoading || data?.connected"
    ref="root"
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
        class="grid grid-cols-2 gap-x-3 gap-y-2 m-0 rounded-lg px-3 py-2 bg-n-slate-2 outline outline-1 outline-n-weak"
        data-testid="store-stats"
      >
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col min-w-0"
          :data-testid="`store-stat-${tile.key}`"
        >
          <dt class="text-xs text-n-slate-11 truncate">{{ tile.label }}</dt>
          <dd class="m-0 text-sm font-semibold truncate text-n-slate-12">
            {{ tile.value }}
          </dd>
        </div>
      </dl>

      <section class="flex flex-col gap-1.5">
        <header class="flex items-baseline justify-between gap-2">
          <p class="text-xs uppercase tracking-wide text-n-slate-11">
            {{ t('STORE_ORDERS.LIST_TITLE') }}
          </p>
          <span class="text-xs tabular-nums text-n-slate-10">
            {{ t('STORE_ORDERS.LIST_COUNT', totalCount) }}
          </span>
        </header>
        <ul
          class="flex flex-col m-0 list-none overflow-hidden rounded-lg bg-n-slate-2 outline outline-1 outline-n-weak divide-y divide-n-weak"
        >
          <StoreOrderItem
            v-for="(order, index) in orders"
            :key="order.id"
            :order="order"
            :open="order.id === openId"
            :position="index + 1"
            :total="totalCount"
            :has-newer="index > 0"
            :has-older="index < orders.length - 1 || hasMore"
            @toggle="toggle(order.id)"
            @newer="step(-1)"
            @older="step(1)"
          />
          <li v-if="hasMore">
            <button
              type="button"
              class="flex items-center justify-center w-full gap-2 px-3 py-2 text-xs text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 disabled:opacity-60"
              :disabled="isLoadingMore"
              data-testid="store-load-more"
              @click="loadMore"
            >
              <Spinner v-if="isLoadingMore" :size="14" />
              {{ t('STORE_ORDERS.LOAD_MORE') }}
            </button>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>
