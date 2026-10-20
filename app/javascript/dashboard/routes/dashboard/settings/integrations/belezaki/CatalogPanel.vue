<script setup>
// What the salon sells and who does it, as belezaki answers it, with the
// button that turns those lists into the sheet's Serviço / Profissional
// options. Shown on the app's page once it is connected.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import BelezakiAPI from 'dashboard/api/integrations/belezaki';
import { formatMoney } from 'dashboard/components/widgets/conversation/belezaki/appointmentFormat';
import { scheduleSummary } from 'dashboard/components/widgets/conversation/belezaki/catalogFormat';

const props = defineProps({
  // The connected hook, for the sync timestamp it carries.
  hook: { type: Object, default: () => ({}) },
});

const { t, locale } = useI18n();

const catalog = ref(null);
const loading = ref(false);
const syncing = ref(false);
const failed = ref(false);
const syncedAt = ref(props.hook?.settings?.catalog_synced_at || '');

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await BelezakiAPI.getCatalog();
    catalog.value = data;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const sync = async () => {
  syncing.value = true;
  try {
    const { data } = await BelezakiAPI.syncCatalog();
    catalog.value = data;
    if (data.sync?.synced) {
      syncedAt.value = new Date().toISOString();
      useAlert(t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SYNC_DONE', data.sync));
    } else {
      useAlert(t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SYNC_FAILED'));
    }
  } catch {
    useAlert(t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SYNC_FAILED'));
  } finally {
    syncing.value = false;
  }
};

onMounted(load);

const status = computed(() =>
  failed.value ? 'unavailable' : catalog.value?.status
);
const services = computed(() => catalog.value?.services || []);
const professionals = computed(() => catalog.value?.professionals || []);
const money = cents => formatMoney(cents, locale.value);
const names = list => (list || []).map(x => x.name).join(', ');
const hours = p => scheduleSummary(p.schedule, locale.value);
const stamp = iso =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(iso));

const thClass = 'text-left text-xs font-medium text-n-slate-11 px-3 py-2';
const tdClass = 'px-3 py-2 text-sm text-n-slate-12 align-top';
</script>

<template>
  <div
    class="mt-4 outline outline-n-container outline-1 bg-n-card rounded-xl p-4 flex flex-col gap-4"
    data-testid="belezaki-catalog"
  >
    <div class="flex items-center justify-between gap-3">
      <div class="flex flex-col">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-11">
          {{
            syncedAt
              ? $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SYNCED_AT', {
                  date: stamp(syncedAt),
                })
              : $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.NEVER_SYNCED')
          }}
        </p>
      </div>
      <NextButton
        :label="$t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SYNC')"
        icon="i-lucide-refresh-cw"
        sm
        :is-loading="syncing"
        data-testid="catalog-sync"
        @click="sync"
      />
    </div>

    <div v-if="loading" class="flex justify-center items-center p-6">
      <Spinner :size="32" class="text-n-brand" />
    </div>
    <p v-else-if="status === 'unavailable'" class="text-sm text-n-ruby-11">
      {{
        $t('CONVERSATION_SIDEBAR.BELEZAKI.UNAVAILABLE', {
          error: catalog?.error || 'network',
        })
      }}
    </p>

    <template v-else-if="status === 'ok'">
      <section class="flex flex-col gap-2">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SERVICES') }}
          <span class="text-n-slate-11">
            {{
              $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.COUNT', {
                count: services.length,
              })
            }}
          </span>
        </h4>
        <div
          class="overflow-x-auto rounded-lg outline outline-1 outline-n-weak"
        >
          <table class="w-full">
            <thead class="bg-n-slate-2">
              <tr>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.NAME') }}
                </th>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.DURATION') }}
                </th>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PRICE') }}
                </th>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.WHO') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="service in services"
                :key="service.id"
                class="border-t border-n-weak"
                data-testid="catalog-service"
              >
                <td :class="tdClass">
                  <span class="font-medium">{{ service.name }}</span>
                  <span
                    v-if="service.is_addon"
                    class="ml-2 text-xs px-1.5 rounded bg-n-slate-3 text-n-slate-12"
                  >
                    {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.ADDON') }}
                  </span>
                </td>
                <td :class="tdClass">
                  {{
                    $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.MINUTES', {
                      count: service.duration_min,
                    })
                  }}
                </td>
                <td :class="tdClass">
                  <span class="font-semibold">{{
                    money(service.price_cents)
                  }}</span>
                  <span
                    v-if="service.is_promo"
                    class="ml-2 text-xs text-n-slate-11 line-through"
                  >
                    {{ money(service.list_price_cents) }}
                  </span>
                  <span
                    v-if="service.is_promo"
                    class="ml-1 text-xs px-1.5 rounded bg-n-amber-5 text-n-amber-12"
                  >
                    {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PROMO') }}
                  </span>
                </td>
                <td :class="tdClass" class="text-n-slate-11">
                  {{ names(service.professionals) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="flex flex-col gap-2">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PROFESSIONALS') }}
          <span class="text-n-slate-11">
            {{
              $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.COUNT', {
                count: professionals.length,
              })
            }}
          </span>
        </h4>
        <div
          class="overflow-x-auto rounded-lg outline outline-1 outline-n-weak"
        >
          <table class="w-full">
            <thead class="bg-n-slate-2">
              <tr>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.NAME') }}
                </th>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.ROLE') }}
                </th>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SERVICES') }}
                </th>
                <th :class="thClass">
                  {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.HOURS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="pro in professionals"
                :key="pro.id"
                class="border-t border-n-weak"
                data-testid="catalog-professional"
              >
                <td :class="tdClass" class="font-medium">{{ pro.name }}</td>
                <td :class="tdClass" class="text-n-slate-11">
                  {{ pro.role || '—' }}
                </td>
                <td :class="tdClass" class="text-n-slate-11">
                  {{
                    pro.performs_all
                      ? $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PERFORMS_ALL')
                      : names(pro.services)
                  }}
                </td>
                <td
                  :class="[
                    tdClass,
                    pro.has_schedule ? 'text-n-slate-11' : 'text-n-amber-11',
                  ]"
                >
                  {{
                    pro.has_schedule
                      ? hours(pro)
                      : $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.NO_SCHEDULE')
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <p v-if="catalog.fetched_at" class="text-xs text-n-slate-10">
        {{
          $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.FETCHED_AT', {
            time: stamp(catalog.fetched_at),
          })
        }}
      </p>
    </template>
  </div>
</template>
