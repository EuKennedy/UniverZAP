<script setup>
// Connecting THIS agent to the operator's own Google Calendar.
//
// Per agent on purpose: one operator may run a salon and a clinic as two
// agents, and their agendas have nothing to do with each other. What the agent
// gets is the account's own calendar, so whatever the owner already put there
// by hand — the dentist, lunch — blocks a slot without anyone copying it here.
//
// The customer never touches any of this. They ask for a time in the chat and
// the agent writes the event; Google is between us and the owner, never
// between us and the customer.
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import AthenasAPI from 'dashboard/api/athenas';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  assistantId: { type: Number, required: true },
  // One agenda per agent. While belezaki holds it, connecting Google here would
  // put two tools called `consultar_horarios` in the same payload.
  blocked: { type: Boolean, default: false },
});

const emit = defineEmits(['connected', 'state']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const connection = ref(null);
const loading = ref(true);
const working = ref(false);

const connected = computed(() => connection.value?.status === 'active');

const fetchConnection = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAPI.calendarConnection(props.assistantId);
    connection.value = data?.connection || null;
  } catch {
    connection.value = null;
  } finally {
    loading.value = false;
    // Reported up so the belezaki block beside this one knows whether the agenda
    // is already taken, without asking the API a second time.
    emit('state', connected.value);
  }
};

const connect = async () => {
  working.value = true;
  try {
    const { data } = await AthenasAPI.startCalendarConnection(
      props.assistantId
    );
    // Full page redirect and not a popup: Google refuses to render its consent
    // screen inside an iframe, and a blocked popup is indistinguishable from a
    // broken button.
    window.location.href = data.url;
  } catch (error) {
    working.value = false;
    const reason =
      error?.response?.data?.error === 'google_oauth_not_configured'
        ? t('ATHENAS.EDIT.CALENDAR.NOT_CONFIGURED')
        : t('ATHENAS.EDIT.CALENDAR.CONNECT_FAILED');
    useAlert(reason);
  }
};

const disconnect = async () => {
  working.value = true;
  try {
    await AthenasAPI.disconnectCalendar(props.assistantId);
    connection.value = null;
    emit('state', false);
    useAlert(t('ATHENAS.EDIT.CALENDAR.DISCONNECTED'));
  } catch {
    useAlert(t('ATHENAS.EDIT.CALENDAR.DISCONNECT_FAILED'));
  } finally {
    working.value = false;
  }
};

// Spelled out rather than built from the reason, so every key is greppable and
// the i18n linter can see them. NO_REFRESH_TOKEN is the one that matters: it
// means the grant would have died in an hour, and the operator has to redo the
// consent screen accepting everything.
const failureMessage = reason => {
  if (reason === 'no_refresh_token')
    return t('ATHENAS.EDIT.CALENDAR.ERRORS.NO_REFRESH_TOKEN');
  if (reason === 'invalid_state')
    return t('ATHENAS.EDIT.CALENDAR.ERRORS.INVALID_STATE');
  if (reason === 'agent_not_found')
    return t('ATHENAS.EDIT.CALENDAR.ERRORS.AGENT_NOT_FOUND');
  return t('ATHENAS.EDIT.CALENDAR.CONNECT_FAILED');
};

// Google sends the operator back here with the outcome in the query string.
// It is stripped afterwards so a refresh does not replay the message.
const consumeCallbackResult = () => {
  const outcome = route.query.calendar;
  if (!outcome) return;

  if (outcome === 'connected') {
    useAlert(t('ATHENAS.EDIT.CALENDAR.CONNECTED'));
    emit('connected');
  } else {
    useAlert(failureMessage(route.query.reason));
  }

  const query = { ...route.query };
  delete query.calendar;
  delete query.reason;
  router.replace({ query });
};

onMounted(async () => {
  await fetchConnection();
  consumeCallbackResult();
});
</script>

<template>
  <div
    class="flex items-center gap-4 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
  >
    <span
      class="inline-flex items-center justify-center flex-shrink-0 rounded-lg size-10"
      :class="connected ? 'bg-n-teal-3' : 'bg-n-alpha-2'"
    >
      <Icon
        icon="i-lucide-calendar-check"
        class="size-5"
        :class="connected ? 'text-n-teal-11' : 'text-n-slate-11'"
      />
    </span>

    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('ATHENAS.EDIT.CALENDAR.TITLE') }}
      </p>
      <p v-if="loading" class="m-0 text-[13px] text-n-slate-11">
        {{ t('ATHENAS.EDIT.CALENDAR.LOADING') }}
      </p>
      <p v-else-if="connected" class="m-0 text-[13px] text-n-slate-11 truncate">
        {{ t('ATHENAS.EDIT.CALENDAR.CONNECTED_AS') }}
        <span class="font-medium text-n-slate-12">{{
          connection.google_email
        }}</span>
      </p>
      <p v-else class="m-0 text-[13px] text-n-slate-11">
        {{ t('ATHENAS.EDIT.CALENDAR.SUBTITLE') }}
      </p>
    </div>

    <!-- Said rather than silently disabled: a dead button reads as a bug, and
         the operator would never learn that belezaki is what is holding the
         agenda. -->
    <p
      v-if="!loading && !connected && blocked"
      class="m-0 text-[12px] text-n-slate-11 max-w-[13rem] text-right"
    >
      {{ t('ATHENAS.EDIT.CALENDAR.BLOCKED') }}
    </p>
    <Button
      v-else-if="!loading && !connected"
      size="sm"
      icon="i-lucide-link"
      :label="t('ATHENAS.EDIT.CALENDAR.CONNECT')"
      :disabled="working"
      @click="connect"
    />
    <Button
      v-else-if="!loading"
      size="sm"
      variant="faded"
      color="ruby"
      :label="t('ATHENAS.EDIT.CALENDAR.DISCONNECT')"
      :disabled="working"
      @click="disconnect"
    />
  </div>
</template>
