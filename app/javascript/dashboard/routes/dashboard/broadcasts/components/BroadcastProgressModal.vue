<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

import BroadcastsAPI from 'dashboard/api/broadcasts';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  broadcastId: { type: Number, required: true },
  open: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const POLL_INTERVAL = 3000;

const status = ref('running');
const counts = ref({ total: 0, sent: 0, failed: 0, pending: 0 });
const recipients = ref([]);
const isLoading = ref(false);
const isPausing = ref(false);

let pollTimer = null;

const isRunning = computed(() => status.value === 'running');
const isPaused = computed(() => status.value === 'paused');
const isCompleted = computed(() => status.value === 'completed');

const statusTone = computed(() => {
  if (isPaused.value) return 'text-n-ruby-11 bg-n-ruby-3';
  if (isCompleted.value) return 'text-n-slate-11 bg-n-alpha-2';
  return 'text-n-teal-11 bg-n-teal-3';
});

const statusLabel = computed(() => {
  if (isPaused.value) return t('BROADCAST.PROGRESS.STATUS_PAUSED');
  if (isCompleted.value) return t('BROADCAST.PROGRESS.STATUS_COMPLETED');
  return t('BROADCAST.PROGRESS.STATUS_RUNNING');
});

const percent = computed(() => {
  const total = Number(counts.value.total) || 0;
  if (!total) return 0;
  const sent = Number(counts.value.sent) || 0;
  return Math.min(100, Math.round((sent / total) * 100));
});

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const fetchRecipients = async () => {
  if (isLoading.value) return;
  isLoading.value = true;
  try {
    const { data } = await BroadcastsAPI.recipients(props.broadcastId);
    status.value = data.status || 'running';
    counts.value = {
      total: data.counts?.total || 0,
      sent: data.counts?.sent || 0,
      failed: data.counts?.failed || 0,
      pending: data.counts?.pending || 0,
    };
    recipients.value = data.recipients || [];
    // Stop polling once the campaign is no longer actively running.
    if (status.value !== 'running') stopPolling();
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.PROGRESS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const startPolling = () => {
  stopPolling();
  // Immediate fetch, then poll on an interval while running.
  fetchRecipients();
  pollTimer = setInterval(() => {
    if (status.value === 'running') fetchRecipients();
    else stopPolling();
  }, POLL_INTERVAL);
};

const onClose = () => {
  stopPolling();
  emit('close');
};

const onPause = async () => {
  isPausing.value = true;
  try {
    await store.dispatch('broadcasts/pause', props.broadcastId);
    await fetchRecipients();
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.PROGRESS.PAUSE_ERROR'));
  } finally {
    isPausing.value = false;
  }
};

// Map a recipient status to its visual treatment.
const statusIcon = recipientStatus => {
  if (recipientStatus === 'failed') return 'i-lucide-x';
  if (['sent', 'delivered', 'read'].includes(recipientStatus)) {
    return 'i-lucide-check';
  }
  return 'i-lucide-clock';
};

const statusIconTone = recipientStatus => {
  if (recipientStatus === 'failed') return 'text-n-ruby-11 bg-n-ruby-3';
  if (['sent', 'delivered', 'read'].includes(recipientStatus)) {
    return 'text-n-teal-11 bg-n-teal-3';
  }
  return 'text-n-slate-11 bg-n-alpha-2';
};

const recipientStatusLabel = recipientStatus =>
  t(`BROADCAST.PROGRESS.RECIPIENT.${recipientStatus.toUpperCase()}`);

const formatTime = sentAt => {
  if (!sentAt) return '';
  const date = new Date(sentAt * 1000);
  return date.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
};

// Start/stop polling cleanly as the modal opens and closes.
watch(
  () => props.open,
  isOpen => {
    if (isOpen) startPolling();
    else stopPolling();
  },
  { immediate: true }
);

onBeforeUnmount(stopPolling);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
      @click.self="onClose"
    >
      <div
        class="flex flex-col w-full max-w-lg max-h-[85vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-2xl overflow-hidden"
      >
        <!-- Header -->
        <header
          class="flex items-center gap-3 px-6 py-4 border-b border-n-weak shrink-0"
        >
          <h2 class="flex-1 text-base font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.PROGRESS.TITLE') }}
          </h2>
          <span
            class="px-2 py-0.5 rounded-full text-[11px] font-medium"
            :class="statusTone"
          >
            {{ statusLabel }}
          </span>
          <button
            type="button"
            class="flex items-center justify-center size-7 rounded-lg text-n-slate-11 cursor-pointer hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
            @click="onClose"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </header>

        <!-- Progress -->
        <div
          class="flex flex-col gap-4 px-6 py-5 border-b border-n-weak shrink-0"
        >
          <div class="flex flex-col gap-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('BROADCAST.PROGRESS.PROGRESS_LABEL') }}
              </span>
              <span class="text-xs font-semibold text-n-teal-11 tabular-nums">
                {{ percent }}%
              </span>
            </div>
            <div class="h-2 w-full rounded-full bg-n-alpha-2 overflow-hidden">
              <div
                class="h-full rounded-full bg-n-teal-9 transition-all duration-500"
                :style="{ width: `${percent}%` }"
              />
            </div>
          </div>

          <div class="grid grid-cols-4 gap-2 text-center">
            <div class="flex flex-col gap-0.5 p-2 rounded-xl bg-n-teal-3">
              <span class="text-base font-semibold text-n-teal-11 tabular-nums">
                {{ counts.sent }}
              </span>
              <span class="text-[11px] text-n-teal-11">
                {{ t('BROADCAST.PROGRESS.SENT') }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5 p-2 rounded-xl bg-n-ruby-3">
              <span class="text-base font-semibold text-n-ruby-11 tabular-nums">
                {{ counts.failed }}
              </span>
              <span class="text-[11px] text-n-ruby-11">
                {{ t('BROADCAST.PROGRESS.FAILED') }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5 p-2 rounded-xl bg-n-alpha-2">
              <span
                class="text-base font-semibold text-n-slate-11 tabular-nums"
              >
                {{ counts.pending }}
              </span>
              <span class="text-[11px] text-n-slate-11">
                {{ t('BROADCAST.PROGRESS.PENDING') }}
              </span>
            </div>
            <div class="flex flex-col gap-0.5 p-2 rounded-xl bg-n-alpha-1">
              <span
                class="text-base font-semibold text-n-slate-12 tabular-nums"
              >
                {{ counts.total }}
              </span>
              <span class="text-[11px] text-n-slate-11">
                {{ t('BROADCAST.PROGRESS.TOTAL') }}
              </span>
            </div>
          </div>
        </div>

        <!-- Log list -->
        <div class="flex-1 min-h-0 overflow-auto px-3 py-2">
          <ul
            v-if="recipients.length"
            class="flex flex-col divide-y divide-n-weak"
          >
            <li
              v-for="recipient in recipients"
              :key="recipient.id"
              class="flex items-start gap-3 px-3 py-2.5"
            >
              <span
                class="flex items-center justify-center size-7 rounded-full shrink-0 mt-0.5"
                :class="statusIconTone(recipient.status)"
              >
                <Icon :icon="statusIcon(recipient.status)" class="size-3.5" />
              </span>
              <div class="flex flex-col min-w-0 flex-1 gap-0.5">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-sm text-n-slate-12 truncate">
                    {{ recipient.name || recipient.phone }}
                  </span>
                  <span
                    v-if="recipient.sent_at"
                    class="text-[11px] text-n-slate-10 tabular-nums shrink-0"
                  >
                    {{ formatTime(recipient.sent_at) }}
                  </span>
                </div>
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    v-if="recipient.name && recipient.phone"
                    class="text-[11px] text-n-slate-10 truncate"
                  >
                    {{ recipient.phone }}
                  </span>
                  <span
                    class="text-[11px] font-medium"
                    :class="
                      recipient.status === 'failed'
                        ? 'text-n-ruby-11'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ recipientStatusLabel(recipient.status) }}
                  </span>
                </div>
                <p
                  v-if="recipient.error"
                  class="text-[11px] text-n-ruby-11 m-0 break-words"
                >
                  {{ recipient.error }}
                </p>
              </div>
            </li>
          </ul>
          <div
            v-else
            class="flex flex-col items-center justify-center gap-2 py-12 text-center"
          >
            <Icon icon="i-lucide-send" class="size-6 text-n-slate-9" />
            <p class="text-xs text-n-slate-10 m-0">
              {{ t('BROADCAST.PROGRESS.EMPTY') }}
            </p>
          </div>
        </div>

        <!-- Footer -->
        <footer
          class="flex items-center justify-end gap-2 px-6 py-4 border-t border-n-weak shrink-0"
        >
          <button
            v-if="isRunning"
            type="button"
            class="inline-flex items-center gap-2 px-4 h-9 rounded-lg bg-n-ruby-9 text-sm font-medium text-white cursor-pointer hover:bg-n-ruby-10 transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
            :disabled="isPausing"
            @click="onPause"
          >
            <Icon
              :icon="isPausing ? 'i-lucide-loader-circle' : 'i-lucide-pause'"
              class="size-4"
              :class="isPausing ? 'animate-spin' : ''"
            />
            <span>{{ t('BROADCAST.PROGRESS.PAUSE') }}</span>
          </button>
          <button
            type="button"
            class="inline-flex items-center px-4 h-9 rounded-lg border border-n-weak text-sm font-medium text-n-slate-12 cursor-pointer hover:bg-n-alpha-2 transition-colors"
            @click="onClose"
          >
            {{ t('BROADCAST.PROGRESS.CLOSE') }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>
