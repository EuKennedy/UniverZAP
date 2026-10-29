<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'next/icon/Icon.vue';
import StoreOrderItem from './StoreOrderItem.vue';
import { formatMoney, formatShortDate } from './storeOrderFormat';

// The customer's orders from the workspace's store, under the sheet. Built to
// be read at a glance while chatting: who she is in the store, four numbers
// with their colour, and the history as light lines that open one at a time
// into the order summary, with a way to walk to the next order (loading
// older pages on the way). Everything comes from the orders already imported
// here: opening a conversation never asks the store.
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

const money = value => formatMoney(value, locale.value);
const shortDate = value => formatShortDate(value, locale.value);

const tiles = computed(() => [
  {
    key: 'orders',
    icon: 'i-lucide-receipt',
    tone: 'bg-n-iris-3 text-n-iris-11',
    label: t('STORE_ORDERS.ORDERS'),
    value: String(metrics.value.orders_count ?? 0),
  },
  {
    key: 'spent',
    icon: 'i-lucide-wallet',
    tone: 'bg-n-teal-3 text-n-teal-11',
    label: t('STORE_ORDERS.SPENT'),
    value: money(metrics.value.total_spent),
  },
  {
    key: 'ticket',
    icon: 'i-lucide-chart-no-axes-column',
    tone: 'bg-n-amber-3 text-n-amber-11',
    label: t('STORE_ORDERS.TICKET'),
    value: money(metrics.value.average_ticket),
  },
  {
    key: 'last',
    icon: 'i-lucide-calendar-clock',
    tone: 'bg-n-violet-3 text-n-violet-11',
    label: t('STORE_ORDERS.LAST'),
    value: shortDate(metrics.value.last_order_at),
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
  <section
    v-if="isLoading || data?.connected"
    ref="root"
    class="flex flex-col gap-3 pt-3 border-t border-n-weak"
    data-testid="store-orders"
  >
    <header class="flex items-center gap-2.5">
      <span
        class="grid rounded-lg size-8 shrink-0 place-content-center bg-brand-gradient"
      >
        <Icon icon="i-lucide-shopping-bag" class="size-4 text-[#06131C]" />
      </span>
      <div class="flex flex-col flex-1 min-w-0">
        <h4 class="m-0 text-sm leading-5 truncate font-520 text-n-slate-12">
          {{ t('STORE_ORDERS.TITLE', { store: storeName }) }}
        </h4>
        <p
          v-if="customerName"
          class="flex items-center min-w-0 gap-1.5 m-0 text-xs leading-4 font-420 text-n-slate-11"
          :title="customer.customer_email"
        >
          <span class="truncate">{{ customerName }}</span>
          <span
            v-if="recurring"
            class="inline-flex items-center gap-1 shrink-0 px-1.5 rounded-full bg-n-amber-3 text-n-amber-11 text-[11px] leading-4"
            data-testid="store-recurring"
          >
            <Icon icon="i-lucide-repeat" class="size-3" />
            {{ t('STORE_ORDERS.RECURRENT') }}
          </span>
        </p>
      </div>
    </header>

    <div v-if="isLoading" class="flex items-center justify-center p-4">
      <Spinner :size="28" class="text-n-brand" />
    </div>

    <p
      v-else-if="!orders.length"
      class="m-0 px-3 py-2.5 text-xs rounded-lg font-420 bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('STORE_ORDERS.EMPTY', { store: storeName }) }}
    </p>

    <template v-else>
      <dl class="grid grid-cols-2 gap-1.5 m-0" data-testid="store-stats">
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex items-center min-w-0 gap-2 px-2 py-1.5 rounded-lg bg-n-alpha-1"
          :data-testid="`store-stat-${tile.key}`"
        >
          <span
            class="grid rounded-md size-7 shrink-0 place-content-center"
            :class="tile.tone"
          >
            <Icon :icon="tile.icon" class="size-3.5" />
          </span>
          <div class="flex flex-col min-w-0">
            <dd
              class="m-0 text-[13px] leading-5 truncate tabular-nums font-520 text-n-slate-12"
            >
              {{ tile.value }}
            </dd>
            <dt class="text-[11px] leading-4 truncate font-420 text-n-slate-10">
              {{ tile.label }}
            </dt>
          </div>
        </div>
      </dl>

      <div class="flex flex-col gap-1">
        <div class="flex items-center justify-between px-1">
          <span class="text-xs font-460 text-n-slate-11">
            {{ t('STORE_ORDERS.LIST_TITLE') }}
          </span>
          <span class="text-xs tabular-nums font-420 text-n-slate-10">
            {{ t('STORE_ORDERS.LIST_COUNT', totalCount) }}
          </span>
        </div>
        <ul class="flex flex-col gap-0.5 m-0 list-none">
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
        </ul>
        <button
          v-if="hasMore"
          type="button"
          class="flex items-center justify-center gap-1.5 py-1.5 text-xs rounded-lg font-420 text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 disabled:opacity-60"
          :disabled="isLoadingMore"
          data-testid="store-load-more"
          @click="loadMore"
        >
          <Spinner v-if="isLoadingMore" :size="12" />
          <Icon v-else icon="i-lucide-chevrons-down" class="size-3.5" />
          {{ t('STORE_ORDERS.LOAD_MORE') }}
        </button>
      </div>
    </template>
  </section>
</template>
