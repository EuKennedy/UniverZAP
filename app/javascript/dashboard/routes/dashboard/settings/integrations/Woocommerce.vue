<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';
import Icon from 'next/icon/Icon.vue';

// UniverZAP: connecting the WooCommerce store of an e-commerce workspace.
// Like SAK, minus the plugin: the REST keys are enough, and the connector
// registers the order webhooks itself.
const { t, locale } = useI18n();
const store = useStore();

const state = ref({ connected: false });
const isLoading = ref(true);
const isSaving = ref(false);
const isSyncing = ref(false);
const confirmingDisconnect = ref(false);
const error = ref('');
const form = reactive({ storeUrl: '', consumerKey: '', consumerSecret: '' });

const canConnect = computed(
  () =>
    form.storeUrl.trim().startsWith('https://') &&
    form.consumerKey.trim() &&
    form.consumerSecret.trim()
);

const lastSynced = computed(() =>
  state.value.last_synced_at
    ? new Date(state.value.last_synced_at).toLocaleString(
        locale.value.replace('_', '-'),
        { dateStyle: 'short', timeStyle: 'short' }
      )
    : t('WOOCOMMERCE.SYNC_PENDING')
);

const stats = computed(() => [
  {
    key: 'orders',
    icon: 'i-lucide-receipt',
    tone: 'bg-n-iris-3 text-n-iris-11',
    label: t('WOOCOMMERCE.STATS.ORDERS'),
    value: state.value.orders_count ?? 0,
  },
  {
    key: 'linked',
    icon: 'i-lucide-user-check',
    tone: 'bg-n-teal-3 text-n-teal-11',
    label: t('WOOCOMMERCE.STATS.LINKED'),
    value: state.value.linked_orders_count ?? 0,
  },
  {
    key: 'synced',
    icon: 'i-lucide-refresh-cw',
    tone: 'bg-n-amber-3 text-n-amber-11',
    label: t('WOOCOMMERCE.STATS.SYNCED'),
    value: lastSynced.value,
  },
]);

const STEPS = computed(() => [
  t('WOOCOMMERCE.STEPS.ONE'),
  t('WOOCOMMERCE.STEPS.TWO'),
  t('WOOCOMMERCE.STEPS.THREE'),
  t('WOOCOMMERCE.STEPS.FOUR'),
]);

const load = async () => {
  try {
    const { data } = await WoocommerceAPI.get();
    state.value = data;
  } finally {
    isLoading.value = false;
  }
};

const refreshIntegrations = () => store.dispatch('integrations/get');

const connect = async () => {
  error.value = '';
  isSaving.value = true;
  try {
    const { data } = await WoocommerceAPI.connect({
      store_url: form.storeUrl.trim(),
      consumer_key: form.consumerKey.trim(),
      consumer_secret: form.consumerSecret.trim(),
    });
    state.value = data;
    Object.assign(form, { storeUrl: '', consumerKey: '', consumerSecret: '' });
    refreshIntegrations();
    useAlert(t('WOOCOMMERCE.CONNECTED'));
  } catch (e) {
    error.value = e?.response?.data?.error || t('WOOCOMMERCE.ERROR');
  } finally {
    isSaving.value = false;
  }
};

const sync = async () => {
  isSyncing.value = true;
  try {
    await WoocommerceAPI.sync();
    useAlert(t('WOOCOMMERCE.SYNC_STARTED'));
  } finally {
    isSyncing.value = false;
  }
};

const disconnect = async () => {
  await WoocommerceAPI.disconnect();
  confirmingDisconnect.value = false;
  state.value = { connected: false };
  refreshIntegrations();
  useAlert(t('WOOCOMMERCE.DISCONNECTED'));
};

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full max-w-4xl gap-5 pb-12 ltr:mr-auto rtl:ml-auto"
  >
    <header class="flex flex-wrap items-center justify-between gap-4">
      <div class="flex items-center min-w-0 gap-3">
        <span
          class="grid flex-shrink-0 shadow-md size-11 rounded-xl place-content-center bg-brand-gradient"
        >
          <Icon icon="i-lucide-shopping-bag" class="size-5 text-[#06131C]" />
        </span>
        <div class="min-w-0">
          <h1 class="text-xl font-bold tracking-tight text-n-slate-12">
            {{ t('WOOCOMMERCE.TITLE') }}
          </h1>
          <p class="text-xs text-n-slate-11">
            {{ t('WOOCOMMERCE.SUBTITLE') }}
          </p>
        </div>
      </div>
      <span
        v-if="state.connected"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold"
        :class="
          state.status === 'failing'
            ? 'bg-n-ruby-3 text-n-ruby-11'
            : 'bg-n-teal-3 text-n-teal-11'
        "
        data-testid="woo-status"
      >
        <span class="rounded-full size-1.5 bg-current" />
        {{
          state.status === 'failing'
            ? t('WOOCOMMERCE.STATUS.FAILING')
            : t('WOOCOMMERCE.STATUS.CONNECTED')
        }}
      </span>
    </header>

    <woot-loading-state v-if="isLoading" />

    <template v-else-if="state.connected">
      <div
        class="flex flex-wrap items-center justify-between gap-3 px-5 py-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div class="min-w-0">
          <p
            class="font-semibold tracking-wider uppercase text-xxs text-n-slate-10"
          >
            {{ t('WOOCOMMERCE.STORE') }}
          </p>
          <a
            :href="state.store_url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-sm font-semibold break-all text-n-slate-12 hover:underline"
          >
            {{ state.store_url }}
          </a>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <NextButton
            faded
            slate
            sm
            icon="i-lucide-refresh-cw"
            :is-loading="isSyncing"
            :label="t('WOOCOMMERCE.SYNC')"
            @click="sync"
          />
          <NextButton
            v-if="!confirmingDisconnect"
            ghost
            ruby
            sm
            icon="i-lucide-unplug"
            :label="t('WOOCOMMERCE.DISCONNECT')"
            @click="confirmingDisconnect = true"
          />
          <template v-else>
            <span class="text-xs text-n-slate-11">
              {{ t('WOOCOMMERCE.DISCONNECT_CONFIRM') }}
            </span>
            <NextButton
              solid
              ruby
              sm
              :label="t('WOOCOMMERCE.DISCONNECT_YES')"
              @click="disconnect"
            />
            <NextButton
              ghost
              slate
              sm
              :label="t('WOOCOMMERCE.CANCEL')"
              @click="confirmingDisconnect = false"
            />
          </template>
        </div>
      </div>

      <p
        v-if="state.last_error"
        class="flex items-start gap-2 px-4 py-3 text-sm rounded-xl bg-n-ruby-3 text-n-ruby-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
        {{ state.last_error }}
      </p>

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div
          v-for="stat in stats"
          :key="stat.key"
          class="flex items-center gap-3 px-4 py-3.5 border shadow-sm rounded-xl border-n-weak bg-n-solid-1"
        >
          <span
            class="grid flex-shrink-0 rounded-lg size-9 place-content-center"
            :class="stat.tone"
          >
            <Icon :icon="stat.icon" class="size-[1.125rem]" />
          </span>
          <div class="min-w-0">
            <p
              class="font-semibold tracking-wider uppercase truncate text-xxs text-n-slate-11"
            >
              {{ stat.label }}
            </p>
            <p class="text-lg font-bold leading-6 text-n-slate-12">
              {{ stat.value }}
            </p>
          </div>
        </div>
      </div>

      <section
        class="grid gap-2 px-5 py-4 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('WOOCOMMERCE.WHAT_HAPPENS.TITLE') }}
        </h2>
        <ul class="grid gap-1.5 m-0 text-sm list-none text-n-slate-11">
          <li class="flex gap-2">
            <Icon
              icon="i-lucide-zap"
              class="size-4 mt-0.5 shrink-0 text-n-teal-11"
            />
            {{ t('WOOCOMMERCE.WHAT_HAPPENS.WEBHOOKS') }}
          </li>
          <li class="flex gap-2">
            <Icon
              icon="i-lucide-user-search"
              class="size-4 mt-0.5 shrink-0 text-n-teal-11"
            />
            {{ t('WOOCOMMERCE.WHAT_HAPPENS.MATCH') }}
          </li>
          <li class="flex gap-2">
            <Icon
              icon="i-lucide-tags"
              class="size-4 mt-0.5 shrink-0 text-n-teal-11"
            />
            {{ t('WOOCOMMERCE.WHAT_HAPPENS.LABELS') }}
          </li>
        </ul>
      </section>
    </template>

    <template v-else>
      <section
        class="grid gap-4 px-5 py-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div>
          <h2 class="text-heading-2 text-n-slate-12">
            {{ t('WOOCOMMERCE.CONNECT.TITLE') }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('WOOCOMMERCE.CONNECT.NOTE') }}
          </p>
        </div>
        <ol class="grid gap-2 m-0 list-none">
          <li
            v-for="(step, index) in STEPS"
            :key="index"
            class="flex gap-3 text-sm text-n-slate-12"
          >
            <span
              class="grid flex-shrink-0 text-xs font-semibold rounded-full size-6 place-content-center bg-n-alpha-2 text-n-slate-11"
            >
              {{ index + 1 }}
            </span>
            <span class="pt-0.5">{{ step }}</span>
          </li>
        </ol>
        <form class="grid gap-3" @submit.prevent="connect">
          <label
            class="grid gap-1 text-sm font-medium text-n-slate-12"
            for="woo-url"
          >
            {{ t('WOOCOMMERCE.CONNECT.URL') }}
            <NextInput
              id="woo-url"
              v-model="form.storeUrl"
              type="url"
              placeholder="https://sualoja.com.br"
              autocomplete="off"
            />
          </label>
          <div class="grid gap-3 md:grid-cols-2">
            <label
              class="grid gap-1 text-sm font-medium text-n-slate-12"
              for="woo-key"
            >
              {{ t('WOOCOMMERCE.CONNECT.KEY') }}
              <NextInput
                id="woo-key"
                v-model="form.consumerKey"
                placeholder="ck_…"
                autocomplete="off"
              />
            </label>
            <label
              class="grid gap-1 text-sm font-medium text-n-slate-12"
              for="woo-secret"
            >
              {{ t('WOOCOMMERCE.CONNECT.SECRET') }}
              <NextInput
                id="woo-secret"
                v-model="form.consumerSecret"
                type="password"
                placeholder="cs_…"
                autocomplete="off"
              />
            </label>
          </div>
          <p
            v-if="error"
            class="px-3 py-2 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-11"
            data-testid="woo-error"
          >
            {{ error }}
          </p>
          <div class="flex justify-end">
            <NextButton
              type="submit"
              icon="i-lucide-plug"
              :is-loading="isSaving"
              :disabled="!canConnect"
              :label="t('WOOCOMMERCE.CONNECT.SUBMIT')"
            />
          </div>
        </form>
      </section>
    </template>
  </div>
</template>
