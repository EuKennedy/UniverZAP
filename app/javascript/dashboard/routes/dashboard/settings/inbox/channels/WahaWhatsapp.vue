<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import WahaChannelAPI from 'dashboard/api/channel/wahaChannel';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const MODE = { NEW: 'new', EXISTING: 'existing' };
const STEPS = { CHOOSE_MODE: 0, FORM: 1, QR: 2 };

const step = ref(STEPS.CHOOSE_MODE);
const mode = ref(MODE.NEW);
const inboxName = ref('');
const sessionName = ref('');
const sessionStatus = ref('');
const sessionMe = ref(null);
const qrCode = ref('');
const isSubmitting = ref(false);
const error = ref('');
let pollTimer = null;

const isWorking = computed(() => sessionStatus.value === 'WORKING');
const phoneNumberFromMe = computed(() => {
  if (!sessionMe.value?.id) return null;
  const digits = String(sessionMe.value.id).split('@')[0].replace(/\D/g, '');
  return digits ? `+${digits}` : null;
});

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

onBeforeUnmount(stopPolling);

const fetchSession = async name => {
  try {
    const { data } = await WahaChannelAPI.showSession(name);
    sessionStatus.value = data.status;
    sessionMe.value = data.me || null;
  } catch (e) {
    if (e?.response?.status !== 404) throw e;
  }
};

const fetchQr = async name => {
  try {
    const { data } = await WahaChannelAPI.sessionQr(name);
    qrCode.value = data.qr;
  } catch (_e) {
    qrCode.value = '';
  }
};

const startPolling = name => {
  stopPolling();
  pollTimer = setInterval(async () => {
    await fetchSession(name);
    if (
      sessionStatus.value === 'SCAN_QR_CODE' ||
      sessionStatus.value === 'STARTING'
    ) {
      if (!qrCode.value) await fetchQr(name);
    } else if (sessionStatus.value === 'WORKING') {
      stopPolling();
      await fetchSession(name);
    } else if (
      sessionStatus.value === 'FAILED' ||
      sessionStatus.value === 'STOPPED'
    ) {
      stopPolling();
    }
  }, 3000);
};

const goToForm = next => {
  mode.value = next;
  error.value = '';
  step.value = STEPS.FORM;
};

const handleNewSession = async () => {
  isSubmitting.value = true;
  error.value = '';
  try {
    const { data } = await WahaChannelAPI.createSession(
      sessionName.value.trim()
    );
    sessionName.value = data.session_name;
    sessionStatus.value = data.status;
    step.value = STEPS.QR;
    await fetchQr(data.session_name);
    startPolling(data.session_name);
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isSubmitting.value = false;
  }
};

const handleConnectExisting = async () => {
  isSubmitting.value = true;
  error.value = '';
  try {
    const { data } = await WahaChannelAPI.connectExisting(
      sessionName.value.trim()
    );
    sessionName.value = data.session_name;
    sessionStatus.value = data.status;
    sessionMe.value = data.me || null;
    step.value = STEPS.QR;
    if (!isWorking.value) {
      await fetchQr(data.session_name);
      startPolling(data.session_name);
    }
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isSubmitting.value = false;
  }
};

const submitForm = () => {
  if (mode.value === MODE.NEW) handleNewSession();
  else handleConnectExisting();
};

const finalizeInbox = async () => {
  isSubmitting.value = true;
  error.value = '';
  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value.trim() || sessionName.value,
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumberFromMe.value,
        provider: 'waha',
        provider_config: { session_name: sessionName.value },
      },
    });
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.WAHA.SUCCESS'));
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: inbox.id },
    });
  } catch (e) {
    error.value = e?.message || t('INBOX_MGMT.ADD.WHATSAPP.WAHA.CREATE_ERROR');
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <header class="flex flex-col gap-1.5">
      <h1 class="text-lg font-semibold text-n-slate-12 tracking-tight">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11 leading-relaxed">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.SUBTITLE') }}
      </p>
    </header>

    <section
      v-if="step === STEPS.CHOOSE_MODE"
      class="grid gap-3 sm:grid-cols-2"
    >
      <button
        type="button"
        class="flex flex-col gap-2 p-5 rounded-xl ring-1 ring-n-weak text-left transition-all hover:ring-n-brand hover:-translate-y-0.5 hover:shadow-[0_8px_20px_-8px_rgba(0,0,0,0.25)]"
        @click="goToForm(MODE.NEW)"
      >
        <span
          class="size-9 rounded-lg bg-n-brand/10 text-n-brand grid place-content-center"
        >
          <span class="i-lucide-qr-code size-5" />
        </span>
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.NEW_SESSION_TITLE') }}
        </h2>
        <p class="text-[12px] text-n-slate-11 leading-relaxed">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.NEW_SESSION_DESC') }}
        </p>
      </button>
      <button
        type="button"
        class="flex flex-col gap-2 p-5 rounded-xl ring-1 ring-n-weak text-left transition-all hover:ring-n-brand hover:-translate-y-0.5 hover:shadow-[0_8px_20px_-8px_rgba(0,0,0,0.25)]"
        @click="goToForm(MODE.EXISTING)"
      >
        <span
          class="size-9 rounded-lg bg-n-blue-3 text-n-blue-11 grid place-content-center"
        >
          <span class="i-lucide-link-2 size-5" />
        </span>
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.EXISTING_TITLE') }}
        </h2>
        <p class="text-[12px] text-n-slate-11 leading-relaxed">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.EXISTING_DESC') }}
        </p>
      </button>
    </section>

    <section
      v-else-if="step === STEPS.FORM"
      class="flex flex-col gap-4 max-w-md"
    >
      <Input
        v-model="inboxName"
        :label="t('INBOX_MGMT.ADD.WHATSAPP.WAHA.INBOX_NAME_LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.WHATSAPP.WAHA.INBOX_NAME_PLACEHOLDER')"
      />
      <Input
        v-model="sessionName"
        :label="t('INBOX_MGMT.ADD.WHATSAPP.WAHA.SESSION_LABEL')"
        :placeholder="
          mode === MODE.NEW
            ? t('INBOX_MGMT.ADD.WHATSAPP.WAHA.SESSION_PLACEHOLDER_NEW')
            : t('INBOX_MGMT.ADD.WHATSAPP.WAHA.SESSION_PLACEHOLDER_EXISTING')
        "
      />
      <p
        v-if="error"
        class="text-[12px] text-n-ruby-11 bg-n-ruby-3 px-3 py-2 rounded-md ring-1 ring-inset ring-n-ruby-6"
      >
        {{ error }}
      </p>
      <div class="flex items-center gap-2">
        <Button
          slate
          faded
          type="button"
          :label="t('INBOX_MGMT.ADD.WHATSAPP.WAHA.BACK')"
          @click="step = STEPS.CHOOSE_MODE"
        />
        <Button
          type="button"
          :label="
            mode === MODE.NEW
              ? t('INBOX_MGMT.ADD.WHATSAPP.WAHA.CREATE_AND_SHOW_QR')
              : t('INBOX_MGMT.ADD.WHATSAPP.WAHA.CONNECT')
          "
          :disabled="!sessionName.trim() || isSubmitting"
          :is-loading="isSubmitting"
          @click="submitForm"
        />
      </div>
    </section>

    <section v-else-if="step === STEPS.QR" class="flex flex-col gap-5 max-w-md">
      <div
        class="flex flex-col items-center gap-3 p-6 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <div v-if="qrCode && !isWorking" class="p-3 rounded-xl bg-white">
          <img
            :src="
              qrCode.startsWith('data:')
                ? qrCode
                : `data:image/png;base64,${qrCode}`
            "
            alt="QR Code"
            class="size-56"
          />
        </div>
        <div
          v-else-if="!isWorking"
          class="flex flex-col items-center gap-2 py-12"
        >
          <span
            class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
          />
          <span class="text-[12px] text-n-slate-11">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.QR_LOADING') }}
          </span>
        </div>
        <div v-else class="flex flex-col items-center gap-2 py-6">
          <span
            class="size-12 rounded-full bg-n-teal-3 grid place-content-center"
          >
            <span class="i-lucide-check size-6 text-n-teal-11" />
          </span>
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.CONNECTED') }}
          </h2>
          <p
            v-if="phoneNumberFromMe"
            class="text-[12px] text-n-slate-11 tabular-nums"
          >
            {{ phoneNumberFromMe }}
          </p>
        </div>

        <p
          v-if="!isWorking"
          class="text-[12px] text-n-slate-11 text-center leading-relaxed max-w-xs"
        >
          {{ t('INBOX_MGMT.ADD.WHATSAPP.WAHA.QR_INSTRUCTIONS') }}
        </p>

        <p
          v-if="sessionStatus"
          class="text-[10px] uppercase tracking-wider font-semibold text-n-slate-10"
        >
          {{ sessionStatus }}
        </p>
      </div>

      <p
        v-if="error"
        class="text-[12px] text-n-ruby-11 bg-n-ruby-3 px-3 py-2 rounded-md ring-1 ring-inset ring-n-ruby-6"
      >
        {{ error }}
      </p>

      <div class="flex items-center justify-between gap-2">
        <Button
          slate
          faded
          type="button"
          :label="t('INBOX_MGMT.ADD.WHATSAPP.WAHA.BACK')"
          @click="
            stopPolling();
            step = STEPS.FORM;
          "
        />
        <Button
          type="button"
          :label="t('INBOX_MGMT.ADD.WHATSAPP.WAHA.FINISH')"
          :disabled="!isWorking || isSubmitting"
          :is-loading="isSubmitting"
          @click="finalizeInbox"
        />
      </div>
    </section>
  </div>
</template>
