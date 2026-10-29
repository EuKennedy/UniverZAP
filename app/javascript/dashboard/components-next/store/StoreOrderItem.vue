<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Icon from 'next/icon/Icon.vue';
import { orderStatus } from './storeOrderStatus';
import { formatMoney, formatShortDate } from './storeOrderFormat';

// One order of the customer's store history. Closed, it is a single light
// line: the status as a coloured icon, the number and the date, the total.
// Open, it shows what was bought, how it was paid and where it is, plus the
// way to the neighbouring orders, without a wall of labels.
const props = defineProps({
  order: { type: Object, required: true },
  open: { type: Boolean, default: false },
  position: { type: Number, required: true },
  total: { type: Number, required: true },
  hasNewer: { type: Boolean, default: false },
  hasOlder: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle', 'newer', 'older']);

const { t, locale } = useI18n();

// A long order would push everything else off the panel.
const VISIBLE_ITEMS = 3;

const showAllItems = ref(false);
// Product photos come from the store; a broken one falls back to the icon.
const brokenImages = ref(new Set());

const money = value => formatMoney(value, locale.value, props.order.currency);
const shortDate = value => formatShortDate(value, locale.value);

const status = computed(() => orderStatus(props.order.status, t));
const items = computed(() => props.order.items || []);
const itemsCount = computed(() =>
  items.value.reduce((sum, item) => sum + (Number(item.quantity) || 0), 0)
);
const visibleItems = computed(() =>
  showAllItems.value ? items.value : items.value.slice(0, VISIBLE_ITEMS)
);
const hiddenItems = computed(() => items.value.length - VISIBLE_ITEMS);
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
      class="flex items-center w-full gap-2.5 px-2.5 py-2 text-left rounded-lg transition-colors hover:bg-n-alpha-2"
      :class="{ 'bg-n-alpha-2': open }"
      :aria-expanded="open"
      :aria-controls="panelId"
      data-testid="store-order-toggle"
      @click="emit('toggle')"
    >
      <span
        class="grid rounded-lg size-8 shrink-0 place-content-center"
        :class="status.tile"
        :title="status.label"
      >
        <Icon :icon="status.icon" class="size-4" />
      </span>
      <span class="flex flex-col flex-1 min-w-0">
        <span class="text-[13px] leading-5 truncate text-n-slate-12 font-460">
          {{ t('STORE_ORDERS.ORDER_NUMBER', { number: order.number }) }}
          <span class="font-420 text-n-slate-10">
            {{ t('STORE_ORDERS.SEPARATOR') }}{{ shortDate(order.placed_at) }}
            {{ t('STORE_ORDERS.SEPARATOR')
            }}{{ t('STORE_ORDERS.ITEMS', itemsCount) }}
          </span>
        </span>
        <span class="text-xs leading-4 truncate font-420" :class="status.text">
          {{ status.label }}
        </span>
      </span>
      <span class="text-[13px] tabular-nums font-520 text-n-slate-12">
        {{ money(order.total) }}
      </span>
      <Icon
        icon="i-lucide-chevron-down"
        class="size-4 shrink-0 text-n-slate-10 transition-transform duration-200"
        :class="{ 'rotate-180': open }"
      />
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
          class="flex flex-col gap-2.5 pt-2 pb-2.5 pl-[3.25rem] pr-2.5"
          data-testid="store-order-summary"
        >
          <ul class="flex flex-col gap-1.5 m-0 list-none">
            <li
              v-for="(item, index) in visibleItems"
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
                <Icon
                  icon="i-lucide-package"
                  class="size-3.5 text-n-slate-10"
                />
              </span>
              <span
                class="flex-1 min-w-0 text-xs truncate font-420 text-n-slate-12"
              >
                {{ item.name }}
              </span>
              <span class="text-xs tabular-nums font-420 text-n-slate-10">
                {{ t('STORE_ORDERS.QUANTITY', { quantity: item.quantity }) }}
              </span>
            </li>
          </ul>
          <button
            v-if="hiddenItems > 0"
            type="button"
            class="self-start text-xs font-420 text-n-slate-11 hover:text-n-slate-12 hover:underline"
            @click="showAllItems = !showAllItems"
          >
            {{
              showAllItems
                ? t('STORE_ORDERS.FEWER_ITEMS')
                : t('STORE_ORDERS.MORE_ITEMS', hiddenItems)
            }}
          </button>

          <div class="flex flex-wrap gap-1.5">
            <span
              v-if="order.payment_method_title"
              class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-2 font-420 text-n-slate-12"
            >
              <Icon
                icon="i-lucide-credit-card"
                class="size-3.5 text-n-teal-11"
              />
              {{ order.payment_method_title }}
              <span v-if="order.paid_at" class="text-n-slate-10">
                {{
                  t('STORE_ORDERS.PAID_ON', { date: shortDate(order.paid_at) })
                }}
              </span>
            </span>
            <button
              v-if="order.tracking?.code"
              type="button"
              class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-n-alpha-2 font-420 text-n-slate-12 hover:bg-n-alpha-3"
              :title="t('STORE_ORDERS.COPY_TRACKING')"
              @click="copyTracking"
            >
              <Icon icon="i-lucide-truck" class="size-3.5 text-n-iris-11" />
              <span class="font-mono">{{ order.tracking.code }}</span>
              <Icon icon="i-lucide-copy" class="size-3 text-n-slate-10" />
            </button>
            <a
              v-if="order.payment_url && order.status === 'pending'"
              :href="order.payment_url"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-n-amber-3 font-420 text-n-amber-11 hover:bg-n-amber-4"
            >
              <Icon icon="i-lucide-link" class="size-3.5" />
              {{ t('STORE_ORDERS.PAYMENT_LINK') }}
            </a>
          </div>

          <div
            class="flex items-center justify-between gap-2 pt-2 border-t border-n-weak"
          >
            <a
              :href="order.admin_url"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 text-xs font-420 text-n-slate-11 hover:text-n-slate-12"
            >
              <Icon icon="i-lucide-external-link" class="size-3.5" />
              {{ t('STORE_ORDERS.OPEN_IN_STORE') }}
            </a>
            <nav
              class="inline-flex items-center gap-0.5"
              :aria-label="t('STORE_ORDERS.NAVIGATION')"
            >
              <button
                type="button"
                class="grid rounded-md size-6 place-content-center text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-30 disabled:pointer-events-none"
                :disabled="!hasNewer"
                :title="t('STORE_ORDERS.NEWER')"
                :aria-label="t('STORE_ORDERS.NEWER')"
                data-testid="store-order-newer"
                @click="emit('newer')"
              >
                <Icon icon="i-lucide-chevron-left" class="size-4" />
              </button>
              <span class="px-1 text-xs tabular-nums font-420 text-n-slate-10">
                {{ t('STORE_ORDERS.POSITION', { current: position, total }) }}
              </span>
              <button
                type="button"
                class="grid rounded-md size-6 place-content-center text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-30 disabled:pointer-events-none"
                :disabled="!hasOlder"
                :title="t('STORE_ORDERS.OLDER')"
                :aria-label="t('STORE_ORDERS.OLDER')"
                data-testid="store-order-older"
                @click="emit('older')"
              >
                <Icon icon="i-lucide-chevron-right" class="size-4" />
              </button>
            </nav>
          </div>
        </div>
      </div>
    </div>
  </li>
</template>
