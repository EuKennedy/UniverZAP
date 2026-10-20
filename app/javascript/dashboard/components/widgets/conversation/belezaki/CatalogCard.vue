<script setup>
// The salon's services and team next to the conversation, searchable, so a
// price or a duration is answered without leaving the chat.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BelezakiAPI from 'dashboard/api/integrations/belezaki';
import { formatMoney } from './appointmentFormat';
import { matches, scheduleSummary } from './catalogFormat';

const { locale } = useI18n();

const catalog = ref(null);
const loading = ref(false);
const failed = ref(false);
const query = ref('');

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

onMounted(load);

const status = computed(() =>
  failed.value ? 'unavailable' : catalog.value?.status
);

const services = computed(() =>
  (catalog.value?.services || []).filter(s =>
    matches(query.value, s.name, ...(s.professionals || []).map(p => p.name))
  )
);
const professionals = computed(() =>
  (catalog.value?.professionals || []).filter(p =>
    matches(query.value, p.name, p.role, ...(p.services || []).map(s => s.name))
  )
);

const money = cents => formatMoney(cents, locale.value);
const names = list => (list || []).map(x => x.name).join(', ');
const hours = p => scheduleSummary(p.schedule, locale.value);
</script>

<template>
  <div class="px-4 py-3 text-sm text-n-slate-12 flex flex-col gap-3">
    <div v-if="loading" class="flex justify-center items-center p-4">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <p v-else-if="status === 'not_linked'" class="text-n-slate-11">
      {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.NOT_LINKED') }}
    </p>

    <p v-else-if="status === 'unavailable'" class="text-n-ruby-11">
      {{
        $t('CONVERSATION_SIDEBAR.BELEZAKI.UNAVAILABLE', {
          error: catalog?.error || 'network',
        })
      }}
    </p>

    <template v-else-if="status === 'ok'">
      <input
        v-model="query"
        type="search"
        class="w-full h-8 px-3 text-sm rounded-lg outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand bg-n-alpha-black2 text-n-slate-12 !mb-0"
        :placeholder="$t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SEARCH')"
        data-testid="catalog-search"
      />

      <section class="flex flex-col">
        <p class="text-xs uppercase tracking-wide text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.SERVICES') }}
        </p>
        <div
          v-for="service in services"
          :key="service.id"
          class="py-2 border-b border-n-weak last:border-b-0 flex flex-col gap-0.5"
          data-testid="catalog-service"
        >
          <div class="flex items-start justify-between gap-2">
            <span class="font-medium text-n-slate-12">{{ service.name }}</span>
            <span class="shrink-0 font-semibold text-n-slate-12">
              {{ money(service.price_cents) }}
            </span>
          </div>
          <div
            class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-n-slate-11"
          >
            <span v-if="service.duration_min">
              {{
                $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.MINUTES', {
                  count: service.duration_min,
                })
              }}
            </span>
            <span v-if="service.is_promo" class="line-through">
              {{ money(service.list_price_cents) }}
            </span>
            <span
              v-if="service.is_promo"
              class="px-1.5 rounded bg-n-amber-5 text-n-amber-12"
            >
              {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PROMO') }}
            </span>
            <span
              v-if="service.is_addon"
              class="px-1.5 rounded bg-n-slate-3 text-n-slate-12"
            >
              {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.ADDON') }}
            </span>
          </div>
          <p
            v-if="service.professionals?.length"
            class="text-xs text-n-slate-11 truncate"
            :title="names(service.professionals)"
          >
            {{ names(service.professionals) }}
          </p>
        </div>
        <p v-if="!services.length" class="text-n-slate-11 py-2">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.EMPTY') }}
        </p>
      </section>

      <section class="flex flex-col">
        <p class="text-xs uppercase tracking-wide text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PROFESSIONALS') }}
        </p>
        <div
          v-for="pro in professionals"
          :key="pro.id"
          class="py-2 border-b border-n-weak last:border-b-0 flex flex-col gap-0.5"
          data-testid="catalog-professional"
        >
          <div class="flex items-baseline justify-between gap-2">
            <span class="font-medium text-n-slate-12">{{ pro.name }}</span>
            <span v-if="pro.role" class="text-xs text-n-slate-11 truncate">
              {{ pro.role }}
            </span>
          </div>
          <p class="text-xs text-n-slate-11">
            {{
              pro.performs_all
                ? $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.PERFORMS_ALL')
                : names(pro.services)
            }}
          </p>
          <p
            class="text-xs"
            :class="pro.has_schedule ? 'text-n-slate-11' : 'text-n-amber-11'"
          >
            {{
              pro.has_schedule
                ? hours(pro)
                : $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.NO_SCHEDULE')
            }}
          </p>
        </div>
        <p v-if="!professionals.length" class="text-n-slate-11 py-2">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.CATALOG.EMPTY') }}
        </p>
      </section>
    </template>
  </div>
</template>
