<script setup>
// The salon's card for the contact of the open conversation: what belezaki
// knows about her, found by the WhatsApp number. Read-only in this phase.
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import BelezakiAPI from 'dashboard/api/integrations/belezaki';
import AppointmentRow from './AppointmentRow.vue';
import { formatDay, formatMoney } from './appointmentFormat';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const { t, locale } = useI18n();
const { isAdmin } = useAdmin();
const getters = useStoreGetters();
const accountId = getters.getCurrentAccountId;

const card = ref(null);
const loading = ref(false);
const failed = ref(false);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await BelezakiAPI.getCustomer(props.contactId);
    card.value = data;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

watch(
  () => props.contactId,
  id => {
    if (id) load();
  },
  { immediate: true }
);

const status = computed(() =>
  failed.value ? 'unavailable' : card.value?.status
);
const salonName = computed(() => card.value?.salon?.name || 'belezaki');
const timezone = computed(() => card.value?.salon?.timezone || '');
const next = computed(() => card.value?.next || null);
const others = computed(() =>
  (card.value?.upcoming || []).filter(row => row.id !== next.value?.id)
);
const history = computed(() => card.value?.history || []);

// The salon's own figures for this person (lookup route only; the older
// agenda route brings no stats and the tiles simply stay out).
const stats = computed(() => card.value?.stats || null);
const tiles = computed(() => {
  if (!stats.value) return [];
  const s = stats.value;
  const money = cents => formatMoney(cents, locale.value);
  return [
    {
      key: 'visits',
      label: t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.VISITS'),
      value: String(s.visits ?? 0),
    },
    {
      key: 'spent',
      label: t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.SPENT'),
      value: money(s.total_spent_cents),
    },
    {
      key: 'ticket',
      label: t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.TICKET'),
      value: money(s.ticket_avg_cents),
    },
    {
      key: 'last_visit',
      label: t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.LAST_VISIT'),
      value: s.last_visit_at
        ? formatDay(s.last_visit_at, timezone.value, locale.value)
        : t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.NEVER'),
    },
    {
      key: 'no_shows',
      label: t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.NO_SHOWS'),
      value: String(s.no_shows ?? 0),
      alert: (s.no_shows ?? 0) > 0,
    },
    {
      key: 'cashback',
      label: t('CONVERSATION_SIDEBAR.BELEZAKI.STATS.CASHBACK'),
      value: money(s.cashback_cents),
    },
  ];
});

const appsURL = computed(() =>
  frontendURL(`accounts/${accountId.value}/settings/integrations/belezaki`)
);
const openApps = () => window.open(appsURL.value, '_blank');
</script>

<template>
  <div
    class="pt-2 border-t border-n-weak text-sm text-n-slate-12 flex flex-col gap-2"
    data-testid="belezaki-card"
  >
    <p class="text-xs uppercase tracking-wide text-n-slate-11">
      {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.TITLE') }}
    </p>
    <div v-if="loading" class="flex justify-center items-center p-4">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <div v-else-if="status === 'not_linked'" class="flex flex-col gap-2">
      <p class="text-n-slate-11">
        {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.NOT_LINKED') }}
      </p>
      <NextButton v-if="isAdmin" faded slate sm @click="openApps">
        {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.OPEN_APPS') }}
      </NextButton>
    </div>

    <div v-else-if="status === 'no_phone'" class="text-n-slate-11">
      {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.NO_PHONE') }}
    </div>

    <div v-else-if="status === 'unavailable'" class="flex flex-col gap-2">
      <p class="text-n-ruby-11">
        {{
          $t('CONVERSATION_SIDEBAR.BELEZAKI.UNAVAILABLE', {
            error: card?.error || 'network',
          })
        }}
      </p>
      <NextButton faded slate sm @click="load">
        {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.RETRY') }}
      </NextButton>
    </div>

    <div v-else-if="status === 'unknown_client'" class="text-n-slate-11">
      {{
        $t('CONVERSATION_SIDEBAR.BELEZAKI.UNKNOWN_CLIENT', { salon: salonName })
      }}
    </div>

    <template v-else-if="status === 'ok'">
      <p
        class="flex items-center gap-2 text-xs text-n-slate-11"
        :title="salonName"
      >
        <span class="truncate">
          {{
            $t('CONVERSATION_SIDEBAR.BELEZAKI.CLIENT_AT', {
              salon: salonName,
              name: card.client.name,
            })
          }}
        </span>
        <span
          v-if="stats?.recurrent"
          class="shrink-0 px-1.5 py-0.5 rounded bg-n-amber-5 text-n-amber-12"
          data-testid="recurrent"
        >
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.RECURRENT') }}
        </span>
      </p>

      <dl
        v-if="tiles.length"
        class="grid grid-cols-2 gap-x-3 gap-y-2 rounded-lg px-3 py-2 bg-n-slate-2 outline outline-1 outline-n-weak"
        data-testid="belezaki-stats"
      >
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col min-w-0"
        >
          <dt class="text-xs text-n-slate-11 truncate">{{ tile.label }}</dt>
          <dd
            class="text-sm font-semibold truncate"
            :class="tile.alert ? 'text-n-ruby-11' : 'text-n-slate-12'"
          >
            {{ tile.value }}
          </dd>
        </div>
      </dl>

      <section
        v-if="next"
        class="rounded-lg px-3 py-1 bg-n-teal-2 outline outline-1 outline-n-teal-5"
      >
        <p class="text-xs uppercase tracking-wide text-n-teal-11 pt-2">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.NEXT') }}
        </p>
        <AppointmentRow :appointment="next" :timezone="timezone" emphasis />
      </section>
      <p
        v-else
        class="rounded-lg px-3 py-2 bg-n-slate-2 outline outline-1 outline-n-weak text-n-slate-11"
      >
        {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.NO_NEXT') }}
      </p>

      <section v-if="others.length" class="flex flex-col">
        <p class="text-xs uppercase tracking-wide text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.UPCOMING') }}
        </p>
        <AppointmentRow
          v-for="row in others"
          :key="row.id"
          :appointment="row"
          :timezone="timezone"
          class="border-b border-n-weak last:border-b-0"
        />
      </section>

      <section class="flex flex-col">
        <p class="text-xs uppercase tracking-wide text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.HISTORY') }}
        </p>
        <AppointmentRow
          v-for="row in history"
          :key="row.id"
          :appointment="row"
          :timezone="timezone"
          class="border-b border-n-weak last:border-b-0"
        />
        <p v-if="!history.length" class="text-n-slate-11 py-2">
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.NO_HISTORY') }}
        </p>
      </section>
    </template>
  </div>
</template>
