<script setup>
// The salon's card for the contact of the open conversation: what belezaki
// knows about her, found by the WhatsApp number. Read-only in this phase.
import { ref, watch, computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import BelezakiAPI from 'dashboard/api/integrations/belezaki';
import AppointmentRow from './AppointmentRow.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

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

const appsURL = computed(() =>
  frontendURL(`accounts/${accountId.value}/settings/integrations/belezaki`)
);
const openApps = () => window.open(appsURL.value, '_blank');
</script>

<template>
  <div class="px-4 py-3 text-sm text-n-slate-12 flex flex-col gap-3">
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
      <p class="text-xs text-n-slate-11 truncate" :title="salonName">
        {{
          $t('CONVERSATION_SIDEBAR.BELEZAKI.CLIENT_AT', {
            salon: salonName,
            name: card.client.name,
          })
        }}
      </p>

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
