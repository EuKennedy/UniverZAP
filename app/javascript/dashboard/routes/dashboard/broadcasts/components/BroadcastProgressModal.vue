<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

import BroadcastsAPI from 'dashboard/api/broadcasts';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { REPORT_FILTERS, funnelOf, widthClass } from '../helpers/broadcastList';

// Relatório do disparo: progresso, o funil enviadas → entregues → lidas →
// responderam, e a lista de destinatários filtrável por resultado, com busca
// e CSV. Atualiza sozinho enquanto o disparo está rodando.
const props = defineProps({
  broadcastId: { type: Number, required: true },
  open: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const POLL_INTERVAL = 3000;
const SEARCH_DEBOUNCE = 300;

const status = ref('running');
const counts = ref({});
const pauseReason = ref(null);
const recipients = ref([]);
const filter = ref('all');
const query = ref('');
const isLoading = ref(false);
const isPausing = ref(false);
const isExporting = ref(false);

let pollTimer = null;
let searchTimer = null;

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

// Processados (enviadas + falhas + puladas) sobre o total.
const processedRatio = computed(() => {
  const total = Number(counts.value.total) || 0;
  if (!total) return 0;
  const done =
    (Number(counts.value.sent) || 0) +
    (Number(counts.value.failed) || 0) +
    (Number(counts.value.skipped) || 0);
  return Math.min(1, done / total);
});
const percentLabel = computed(
  () => `${Math.round(processedRatio.value * 100)}%`
);

const funnel = computed(() => funnelOf(counts.value));
const ratioLabel = ratio => `${Math.round(ratio * 100)}%`;

const filterCount = key =>
  key === 'all' ? counts.value.total || 0 : counts.value[key] || 0;

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
    const { data } = await BroadcastsAPI.recipients(props.broadcastId, {
      filter: filter.value,
      q: query.value.trim(),
    });
    status.value = data.status || 'running';
    pauseReason.value = data.pause_reason;
    counts.value = data.counts || {};
    recipients.value = data.recipients || [];
    if (status.value !== 'running') stopPolling();
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.PROGRESS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const startPolling = () => {
  stopPolling();
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

const pickFilter = key => {
  filter.value = key;
  fetchRecipients();
};

watch(query, () => {
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchRecipients, SEARCH_DEBOUNCE);
});

const exportCsv = async () => {
  isExporting.value = true;
  try {
    const { data } = await BroadcastsAPI.exportRecipients(props.broadcastId, {
      filter: filter.value,
      q: query.value.trim(),
    });
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `disparo-${props.broadcastId}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    useAlert(t('BROADCAST.PROGRESS.EXPORT_ERROR'));
  } finally {
    isExporting.value = false;
  }
};

const resultOf = recipient => {
  if (recipient.status === 'skipped') return 'skipped';
  if (recipient.status === 'failed' || recipient.delivery === 'failed')
    return 'failed';
  if (recipient.replied_at) return 'replied';
  if (['delivered', 'read'].includes(recipient.delivery))
    return recipient.delivery;
  return recipient.status;
};

const RESULT_STYLE = {
  failed: { icon: 'i-lucide-x', tone: 'text-n-ruby-11 bg-n-ruby-3' },
  skipped: {
    icon: 'i-lucide-shield-check',
    tone: 'text-n-slate-11 bg-n-alpha-2',
  },
  replied: {
    icon: 'i-lucide-message-circle-reply',
    tone: 'text-n-amber-11 bg-n-amber-3',
  },
  read: { icon: 'i-lucide-check-check', tone: 'text-n-teal-11 bg-n-teal-3' },
  delivered: {
    icon: 'i-lucide-check-check',
    tone: 'text-n-teal-11 bg-n-teal-3',
  },
  sent: { icon: 'i-lucide-check', tone: 'text-n-teal-11 bg-n-teal-3' },
  pending: { icon: 'i-lucide-clock', tone: 'text-n-slate-11 bg-n-alpha-2' },
};
const styleOf = recipient =>
  RESULT_STYLE[resultOf(recipient)] || RESULT_STYLE.pending;

const resultLabel = recipient => {
  if (recipient.status === 'skipped' && recipient.skip_reason) {
    return t(`BROADCAST.PREVIEW.SKIP.${recipient.skip_reason.toUpperCase()}`);
  }
  return t(`BROADCAST.PROGRESS.RECIPIENT.${resultOf(recipient).toUpperCase()}`);
};

const formatTime = seconds => {
  if (!seconds) return '';
  return new Date(seconds * 1000).toLocaleString([], {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

watch(
  () => props.open,
  isOpen => {
    if (isOpen) startPolling();
    else stopPolling();
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  stopPolling();
  if (searchTimer) clearTimeout(searchTimer);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
      @click.self="onClose"
    >
      <div
        class="flex flex-col w-full max-w-2xl max-h-[88vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-2xl overflow-hidden"
        data-testid="broadcast-report-modal"
      >
        <header
          class="flex items-center gap-3 px-6 py-4 border-b border-n-weak shrink-0"
        >
          <span
            class="flex items-center justify-center rounded-xl size-9 shrink-0 bg-brand-gradient text-[#06131C]"
          >
            <span class="i-lucide-chart-spline size-4" />
          </span>
          <h2 class="flex-1 m-0 text-base font-semibold text-n-slate-12">
            {{ t('BROADCAST.PROGRESS.TITLE') }}
          </h2>
          <span
            class="px-2 py-0.5 rounded-full text-[11px] font-medium"
            :class="statusTone"
          >
            {{ statusLabel }}
          </span>
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-x"
            @click="onClose"
          />
        </header>

        <div
          class="flex flex-col gap-4 px-6 py-5 border-b border-n-weak shrink-0"
        >
          <div class="flex flex-col gap-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-medium text-n-slate-11">
                {{
                  t('BROADCAST.PROGRESS.PROCESSED', {
                    total: counts.total || 0,
                    pending: counts.pending || 0,
                  })
                }}
              </span>
              <span class="text-xs font-semibold tabular-nums text-n-teal-11">
                {{ percentLabel }}
              </span>
            </div>
            <div class="w-full h-2 overflow-hidden rounded-full bg-n-alpha-2">
              <div
                class="h-full transition-all duration-500 rounded-full bg-n-teal-9"
                :class="widthClass(processedRatio)"
              />
            </div>
          </div>

          <div
            class="grid grid-cols-2 gap-2 sm:grid-cols-4"
            data-testid="broadcast-funnel"
          >
            <div
              v-for="step in funnel"
              :key="step.key"
              class="flex flex-col gap-1.5 p-3 rounded-xl bg-n-alpha-1"
            >
              <span
                class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-11"
              >
                {{ t(`BROADCAST.PROGRESS.FUNNEL.${step.key.toUpperCase()}`) }}
              </span>
              <span
                class="text-lg font-bold leading-none tabular-nums text-n-slate-12"
              >
                {{ step.value }}
              </span>
              <span class="overflow-hidden h-1 rounded-full bg-n-alpha-2">
                <span
                  class="block h-full rounded-full bg-n-teal-9"
                  :class="widthClass(step.ratio)"
                />
              </span>
              <span class="text-[10px] tabular-nums text-n-slate-10">
                {{ ratioLabel(step.ratio) }}
              </span>
            </div>
          </div>

          <div class="flex gap-2 text-xs">
            <span class="px-2 py-1 rounded-lg bg-n-ruby-3 text-n-ruby-11">
              {{
                t(
                  'BROADCAST.PROGRESS.FAILED_COUNT',
                  { count: counts.failed || 0 },
                  counts.failed || 0
                )
              }}
            </span>
            <span class="px-2 py-1 rounded-lg bg-n-alpha-2 text-n-slate-11">
              {{
                t(
                  'BROADCAST.PROGRESS.SKIPPED_COUNT',
                  { count: counts.skipped || 0 },
                  counts.skipped || 0
                )
              }}
            </span>
          </div>

          <p
            v-if="isPaused && pauseReason === 'failures'"
            class="m-0 px-3 py-2 rounded-lg text-xs bg-n-ruby-3 text-n-ruby-11"
          >
            {{ t('BROADCAST.COMPOSER.PAUSED_BY_FAILURES') }}
          </p>
        </div>

        <div class="flex flex-col gap-2 px-6 pt-4 shrink-0">
          <div class="flex flex-wrap gap-1" data-testid="report-filters">
            <button
              v-for="key in REPORT_FILTERS"
              :key="key"
              type="button"
              class="flex items-center gap-1 px-2.5 py-1 text-xs rounded-full border transition-colors"
              :class="
                filter === key
                  ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
                  : 'border-n-weak text-n-slate-11 hover:border-n-slate-8'
              "
              :data-testid="`report-filter-${key}`"
              @click="pickFilter(key)"
            >
              {{ t(`BROADCAST.PROGRESS.FILTERS.${key.toUpperCase()}`) }}
              <span class="tabular-nums opacity-70">{{
                filterCount(key)
              }}</span>
            </button>
          </div>
          <div class="flex items-center gap-2">
            <label class="relative flex-1">
              <span
                class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-3.5 start-3 top-1/2 text-n-slate-10"
              />
              <input
                v-model="query"
                type="search"
                :placeholder="t('BROADCAST.PROGRESS.SEARCH')"
                class="w-full h-8 !ps-8 pe-3 rounded-lg bg-n-solid-2 border border-n-weak text-[13px] text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
                data-testid="report-search"
              />
            </label>
            <Button
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-download"
              :label="t('BROADCAST.PROGRESS.EXPORT')"
              :is-loading="isExporting"
              data-testid="report-export"
              @click="exportCsv"
            />
          </div>
        </div>

        <div class="flex-1 min-h-0 px-3 py-2 overflow-auto">
          <ul
            v-if="recipients.length"
            class="flex flex-col m-0 divide-y divide-n-weak"
          >
            <li
              v-for="recipient in recipients"
              :key="recipient.id"
              class="flex items-start gap-3 px-3 py-2.5 list-none"
              data-testid="report-row"
            >
              <span
                class="flex items-center justify-center size-7 rounded-full shrink-0 mt-0.5"
                :class="styleOf(recipient).tone"
              >
                <Icon :icon="styleOf(recipient).icon" class="size-3.5" />
              </span>
              <div class="flex flex-col flex-1 min-w-0 gap-0.5">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ recipient.name || recipient.phone }}
                  </span>
                  <span
                    v-if="recipient.sent_at"
                    class="text-[11px] tabular-nums shrink-0 text-n-slate-10"
                  >
                    {{ formatTime(recipient.sent_at) }}
                  </span>
                </div>
                <div class="flex items-center min-w-0 gap-2">
                  <span
                    v-if="recipient.name && recipient.phone"
                    class="text-[11px] truncate text-n-slate-10"
                  >
                    {{ recipient.phone }}
                  </span>
                  <span
                    class="text-[11px] font-medium"
                    :class="
                      resultOf(recipient) === 'failed'
                        ? 'text-n-ruby-11'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ resultLabel(recipient) }}
                  </span>
                </div>
                <p
                  v-if="recipient.error"
                  class="m-0 text-[11px] break-words text-n-ruby-11"
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
            <Icon icon="i-lucide-search-x" class="size-6 text-n-slate-9" />
            <p class="m-0 text-xs text-n-slate-10">
              {{
                filter === 'all' && !query
                  ? t('BROADCAST.PROGRESS.EMPTY')
                  : t('BROADCAST.PROGRESS.NO_MATCH')
              }}
            </p>
          </div>
        </div>

        <footer
          class="flex items-center justify-end gap-2 px-6 py-4 border-t border-n-weak shrink-0"
        >
          <Button
            v-if="isRunning"
            color="ruby"
            icon="i-lucide-pause"
            :label="t('BROADCAST.PROGRESS.PAUSE')"
            :is-loading="isPausing"
            @click="onPause"
          />
          <Button
            variant="outline"
            color="slate"
            :label="t('BROADCAST.PROGRESS.CLOSE')"
            @click="onClose"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>
