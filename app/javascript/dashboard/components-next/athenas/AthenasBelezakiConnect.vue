<script setup>
// Connecting THIS agent to the salon it already runs on belezaki.
//
// There is no OAuth to run here, unlike the Google block above: the belezaki
// agent API authenticates server-to-server with a shared key plus the salon id
// in a header. So "connecting" is the operator confirming WHICH salon this agent
// books on — and the POST proves the binding works by reading the salon back
// before anything is stored.
//
// A salon already on belezaki keeps its services, prices, professionals, hours
// and blocks there. Connecting reads them, which is the whole point: asking the
// owner to type all of it a second time would create a second truth that
// diverges in the first week.
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  assistantId: { type: Number, required: true },
  // One agenda per agent: two would put two tools called `consultar_horarios`
  // in the same payload, which the model API rejects outright.
  googleConnected: { type: Boolean, default: false },
});

const emit = defineEmits(['connected', 'disconnectGoogle']);

const { t } = useI18n();

const connection = ref(null);
const loading = ref(true);
const working = ref(false);
const showOnlyOne = ref(false);

const connected = computed(() => connection.value?.status === 'active');

// The agenda failed and the row says so. Shown because the alternative is a card
// that reads "connected" while the agent has quietly stopped being able to book,
// and nobody finds out until a customer does.
const agendaFailed = computed(() => Boolean(connection.value?.last_error));

const fetchConnection = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAPI.belezakiConnection(props.assistantId);
    connection.value = data?.connection || null;
  } catch {
    connection.value = null;
  } finally {
    loading.value = false;
    emit('connected', connected.value);
  }
};

// Spelled out rather than built from the code, so every key is greppable and the
// i18n linter can see them. The four causes have four different fixes, and three
// of them are not the operator's to make.
const failureMessage = code => {
  if (code === 'not_linked')
    return t('ATHENAS.EDIT.BELEZAKI.ERRORS.NOT_LINKED');
  if (code === 'not_configured')
    return t('ATHENAS.EDIT.BELEZAKI.ERRORS.NOT_CONFIGURED');
  if (code === 'agenda_taken')
    return t('ATHENAS.EDIT.BELEZAKI.ERRORS.AGENDA_TAKEN');
  return t('ATHENAS.EDIT.BELEZAKI.ERRORS.PROBE_FAILED');
};

const connect = async () => {
  // Asked here rather than after a round trip: the operator gets the reason and
  // the way out in the same click.
  if (props.googleConnected) {
    showOnlyOne.value = true;
    return;
  }

  working.value = true;
  try {
    const { data } = await AthenasAPI.connectBelezaki(props.assistantId);
    connection.value = data.connection;
    useAlert(t('ATHENAS.EDIT.BELEZAKI.CONNECTED'));
    emit('connected', true);
  } catch (error) {
    useAlert(failureMessage(error?.response?.data?.error));
  } finally {
    working.value = false;
  }
};

const disconnect = async () => {
  working.value = true;
  try {
    await AthenasAPI.disconnectBelezaki(props.assistantId);
    connection.value = null;
    useAlert(t('ATHENAS.EDIT.BELEZAKI.DISCONNECTED'));
    emit('connected', false);
  } catch {
    useAlert(t('ATHENAS.EDIT.BELEZAKI.DISCONNECT_FAILED'));
  } finally {
    working.value = false;
  }
};

onMounted(fetchConnection);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      class="flex items-center gap-4 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
    >
      <span
        class="inline-flex items-center justify-center flex-shrink-0 rounded-lg size-10"
        :class="connected ? 'bg-n-teal-3' : 'bg-n-alpha-2'"
      >
        <Icon
          icon="i-lucide-scissors"
          class="size-5"
          :class="connected ? 'text-n-teal-11' : 'text-n-slate-11'"
        />
      </span>

      <div class="flex flex-col flex-1 min-w-0 gap-0.5">
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('ATHENAS.EDIT.BELEZAKI.TITLE') }}
        </p>
        <p v-if="loading" class="m-0 text-[13px] text-n-slate-11">
          {{ t('ATHENAS.EDIT.BELEZAKI.LOADING') }}
        </p>
        <p
          v-else-if="connected"
          class="m-0 text-[13px] text-n-slate-11 truncate"
        >
          {{ t('ATHENAS.EDIT.BELEZAKI.CONNECTED_TO') }}
          <span class="font-medium text-n-slate-12">
            {{ connection.salon_name }}
          </span>
        </p>
        <p v-else class="m-0 text-[13px] text-n-slate-11">
          {{ t('ATHENAS.EDIT.BELEZAKI.SUBTITLE') }}
        </p>

        <!-- Two different messages because the fixes are different: a dropped
             binding is reconnected here, a configuration failure is ours. -->
        <p
          v-if="agendaFailed"
          class="m-0 text-[12px] text-n-amber-11 flex items-center gap-1"
        >
          <Icon icon="i-lucide-triangle-alert" class="size-3 flex-shrink-0" />
          {{
            connected
              ? t('ATHENAS.EDIT.BELEZAKI.LAST_FAILURE')
              : t('ATHENAS.EDIT.BELEZAKI.DROPPED')
          }}
        </p>
      </div>

      <Button
        v-if="!loading && !connected"
        size="sm"
        icon="i-lucide-link"
        :label="t('ATHENAS.EDIT.BELEZAKI.CONNECT')"
        :disabled="working"
        @click="connect"
      />
      <Button
        v-else-if="!loading"
        size="sm"
        variant="faded"
        color="ruby"
        :label="t('ATHENAS.EDIT.BELEZAKI.DISCONNECT')"
        :disabled="working"
        @click="disconnect"
      />
    </div>

    <!-- Said where the operator can act on it, with the way out inside. -->
    <div
      v-if="showOnlyOne"
      class="flex flex-col gap-2 p-4 border rounded-xl border-n-amber-6 bg-n-amber-3"
    >
      <p class="m-0 text-[13px] font-medium text-n-amber-12">
        {{ t('ATHENAS.EDIT.BELEZAKI.ONLY_ONE') }}
      </p>
      <p class="m-0 text-[12px] text-n-amber-11">
        {{ t('ATHENAS.EDIT.BELEZAKI.ONLY_ONE_BODY') }}
      </p>
      <div class="flex gap-2 mt-1">
        <Button
          size="sm"
          color="ruby"
          :label="t('ATHENAS.EDIT.BELEZAKI.DISCONNECT_GOOGLE')"
          @click="emit('disconnectGoogle')"
        />
        <Button
          size="sm"
          variant="ghost"
          :label="t('ATHENAS.EDIT.BELEZAKI.CANCEL')"
          @click="showOnlyOne = false"
        />
      </div>
    </div>
  </div>
</template>
