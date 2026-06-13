<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import BroadcastsAPI from 'dashboard/api/broadcasts';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  broadcastId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const labels = useMapGetter('labels/getLabels');
const funnels = useMapGetter('funnels/getFunnels');
const uiFlags = useMapGetter('broadcasts/getUIFlags');

const THROTTLE_DEFAULTS = {
  batch_min: 3,
  batch_max: 8,
  delay_min: 20,
  delay_max: 60,
  daily_cap: 500,
};

const broadcast = ref(null);

// Local editable form state — synced from the loaded broadcast.
const form = reactive({
  mode: 'waha',
  message: {
    text: '',
    attachment: null,
    attachment_name: '',
    caption: '',
    template: { name: '', language: 'pt_BR', namespace: '' },
  },
  audience: {
    contact_label_ids: [],
    conversation_label_ids: [],
    funnel_stage_ids: [],
    contact_ids: [],
    phone_numbers: [],
  },
  throttle: { ...THROTTLE_DEFAULTS },
  scheduled_at: '',
});

const audienceCount = ref(null);
const isPreviewing = ref(false);

const status = computed(() => broadcast.value?.status || 'draft');

const statusTone = computed(
  () =>
    ({
      running: 'text-n-teal-11 bg-n-teal-3',
      scheduled: 'text-n-teal-11 bg-n-teal-3',
      draft: 'text-n-amber-11 bg-n-amber-3',
      completed: 'text-n-slate-11 bg-n-alpha-2',
      paused: 'text-n-ruby-11 bg-n-ruby-3',
    })[status.value] || 'text-n-slate-11 bg-n-alpha-2'
);

const canLaunch = computed(
  () =>
    ['draft', 'paused'].includes(status.value) &&
    Number(audienceCount.value) > 0
);

const isRunning = computed(() => status.value === 'running');

// Convert an ISO timestamp to the value a datetime-local input expects.
const toLocalInput = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60000).toISOString().slice(0, 16);
};

const hydrate = record => {
  broadcast.value = record;
  form.mode = record.mode || 'waha';
  const msg = record.message || {};
  form.message.text = msg.text || '';
  form.message.attachment = msg.attachment || null;
  form.message.attachment_name = msg.attachment_name || '';
  form.message.caption = msg.caption || '';
  form.message.template = {
    name: msg.template?.name || '',
    language: msg.template?.language || 'pt_BR',
    namespace: msg.template?.namespace || '',
  };
  const aud = record.audience || {};
  form.audience.contact_label_ids = aud.contact_label_ids || [];
  form.audience.conversation_label_ids = aud.conversation_label_ids || [];
  form.audience.funnel_stage_ids = aud.funnel_stage_ids || [];
  form.audience.contact_ids = aud.contact_ids || [];
  form.audience.phone_numbers = aud.phone_numbers || [];
  form.throttle = { ...THROTTLE_DEFAULTS, ...(record.throttle || {}) };
  form.scheduled_at = toLocalInput(record.scheduled_at);
};

onMounted(async () => {
  store.dispatch('labels/get');
  store.dispatch('funnels/get');
  try {
    const data = await store.dispatch('broadcasts/show', props.broadcastId);
    hydrate(data);
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.LOAD_ERROR'));
  }
});

const toggleId = (list, id) => {
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

const buildPayload = () => {
  const message =
    form.mode === 'waha'
      ? {
          text: form.message.text,
          attachment: form.message.attachment,
          attachment_name: form.message.attachment_name,
          caption: form.message.caption,
        }
      : { template: { ...form.message.template } };
  return {
    id: props.broadcastId,
    mode: form.mode,
    message,
    audience: { ...form.audience },
    throttle: { ...form.throttle },
    scheduled_at: form.scheduled_at
      ? new Date(form.scheduled_at).toISOString()
      : null,
  };
};

const refreshAudience = async () => {
  isPreviewing.value = true;
  try {
    const { data } = await BroadcastsAPI.audiencePreview(props.broadcastId);
    audienceCount.value = data.count;
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.PREVIEW_ERROR'));
  } finally {
    isPreviewing.value = false;
  }
};

const save = async () => {
  try {
    const data = await store.dispatch('broadcasts/update', buildPayload());
    hydrate(data);
    useAlert(t('BROADCAST.COMPOSER.SAVED'));
    await refreshAudience();
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.SAVE_ERROR'));
  }
};

const launch = async () => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('BROADCAST.COMPOSER.LAUNCH_CONFIRM', { count: audienceCount.value })
    )
  )
    return;
  try {
    const data = await store.dispatch('broadcasts/launch', props.broadcastId);
    hydrate(data);
    useAlert(t('BROADCAST.COMPOSER.LAUNCHED'));
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.LAUNCH_ERROR'));
  }
};

const pause = async () => {
  try {
    const data = await store.dispatch('broadcasts/pause', props.broadcastId);
    hydrate(data);
    useAlert(t('BROADCAST.COMPOSER.PAUSED'));
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.PAUSE_ERROR'));
  }
};

const goBack = () => {
  router.push(accountScopedRoute('broadcasts_index'));
};

watch(
  () => form.mode,
  () => {
    audienceCount.value = null;
  }
);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-5 border-b border-n-weak shrink-0"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-arrow-left"
          @click="goBack"
        />
        <div class="flex flex-col gap-0.5 min-w-0">
          <h1 class="text-lg font-semibold text-n-slate-12 m-0 truncate">
            {{ broadcast?.name || t('BROADCAST.COMPOSER.TITLE') }}
          </h1>
          <span
            class="self-start px-2 py-0.5 rounded-full text-[11px] font-medium capitalize"
            :class="statusTone"
          >
            {{ t(`BROADCAST.STATUS.${status.toUpperCase()}`) }}
          </span>
        </div>
      </div>
    </header>

    <div
      class="flex-1 grid grid-cols-1 xl:grid-cols-[1fr_360px] overflow-hidden"
    >
      <!-- Left: config form -->
      <div class="overflow-auto px-8 py-6 flex flex-col gap-8">
        <!-- Mode -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.MODE_TITLE') }}
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <button
              v-for="m in ['waha', 'official']"
              :key="m"
              type="button"
              class="flex items-start gap-3 p-4 rounded-xl border text-left cursor-pointer transition-all"
              :class="
                form.mode === m
                  ? 'border-n-teal-8 bg-n-teal-3/50 ring-1 ring-n-teal-7/40'
                  : 'border-n-weak hover:border-n-slate-6'
              "
              @click="form.mode = m"
            >
              <span
                class="flex items-center justify-center size-9 rounded-lg shrink-0"
                :class="
                  form.mode === m
                    ? 'bg-n-teal-9 text-white'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                <Icon
                  :icon="
                    m === 'waha'
                      ? 'i-lucide-message-circle'
                      : 'i-lucide-badge-check'
                  "
                  class="size-4"
                />
              </span>
              <span class="flex flex-col gap-0.5 min-w-0">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t(`BROADCAST.MODE.${m.toUpperCase()}.LABEL`) }}
                </span>
                <span class="text-xs text-n-slate-11 leading-snug">
                  {{ t(`BROADCAST.MODE.${m.toUpperCase()}.HINT`) }}
                </span>
              </span>
            </button>
          </div>
        </section>

        <!-- Message -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.MESSAGE_TITLE') }}
          </h2>

          <template v-if="form.mode === 'waha'">
            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('BROADCAST.MESSAGE.TEXT') }}
              </span>
              <textarea
                v-model="form.message.text"
                rows="5"
                :placeholder="t('BROADCAST.MESSAGE.TEXT_PLACEHOLDER')"
                class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 resize-y"
              />
            </label>
            <!-- TODO: replace with a real media uploader (signed_id). For now
                 this is just a manual attachment name reference. -->
            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('BROADCAST.MESSAGE.MEDIA') }}
              </span>
              <input
                v-model="form.message.attachment_name"
                type="text"
                :placeholder="t('BROADCAST.MESSAGE.MEDIA_PLACEHOLDER')"
                class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
              />
              <p class="text-[11px] text-n-slate-10 m-0">
                {{ t('BROADCAST.MESSAGE.MEDIA_HINT') }}
              </p>
            </label>
          </template>

          <template v-else>
            <!-- TODO: replace manual entry with a template picker that loads
                 approved Meta templates by name/language/namespace. -->
            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('BROADCAST.MESSAGE.TEMPLATE_NAME') }}
              </span>
              <input
                v-model="form.message.template.name"
                type="text"
                :placeholder="t('BROADCAST.MESSAGE.TEMPLATE_NAME_PLACEHOLDER')"
                class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
              />
            </label>
            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('BROADCAST.MESSAGE.TEMPLATE_LANGUAGE') }}
              </span>
              <input
                v-model="form.message.template.language"
                type="text"
                :placeholder="
                  t('BROADCAST.MESSAGE.TEMPLATE_LANGUAGE_PLACEHOLDER')
                "
                class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
              />
            </label>
          </template>
        </section>

        <!-- Audience -->
        <section class="flex flex-col gap-4">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.AUDIENCE_TITLE') }}
          </h2>

          <!-- Contact labels -->
          <div class="flex flex-col gap-2">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('BROADCAST.AUDIENCE.CONTACT_LABELS') }}
            </span>
            <div v-if="labels.length" class="flex flex-wrap gap-2">
              <button
                v-for="label in labels"
                :key="`cl-${label.id}`"
                type="button"
                class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium cursor-pointer transition-all"
                :class="
                  form.audience.contact_label_ids.includes(label.id)
                    ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                    : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
                "
                @click="toggleId(form.audience.contact_label_ids, label.id)"
              >
                <span
                  class="size-2 rounded-sm"
                  :style="{ backgroundColor: label.color }"
                />
                {{ label.title }}
              </button>
            </div>
            <p v-else class="text-[11px] text-n-slate-10 m-0">
              {{ t('BROADCAST.AUDIENCE.NO_LABELS') }}
            </p>
          </div>

          <!-- Conversation labels -->
          <div class="flex flex-col gap-2">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('BROADCAST.AUDIENCE.CONVERSATION_LABELS') }}
            </span>
            <div v-if="labels.length" class="flex flex-wrap gap-2">
              <button
                v-for="label in labels"
                :key="`vl-${label.id}`"
                type="button"
                class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium cursor-pointer transition-all"
                :class="
                  form.audience.conversation_label_ids.includes(label.id)
                    ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                    : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
                "
                @click="
                  toggleId(form.audience.conversation_label_ids, label.id)
                "
              >
                <span
                  class="size-2 rounded-sm"
                  :style="{ backgroundColor: label.color }"
                />
                {{ label.title }}
              </button>
            </div>
            <p v-else class="text-[11px] text-n-slate-10 m-0">
              {{ t('BROADCAST.AUDIENCE.NO_LABELS') }}
            </p>
          </div>

          <!-- Kanban stages -->
          <div class="flex flex-col gap-3">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('BROADCAST.AUDIENCE.FUNNEL_STAGES') }}
            </span>
            <div
              v-for="funnel in funnels"
              :key="funnel.id"
              class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 border border-n-weak"
            >
              <span class="text-xs font-semibold text-n-slate-12">
                {{ funnel.name }}
              </span>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="stage in funnel.stages || []"
                  :key="`st-${funnel.id}-${stage.id}`"
                  type="button"
                  class="inline-flex items-center px-2.5 py-1 rounded-full border text-xs font-medium cursor-pointer transition-all"
                  :class="
                    form.audience.funnel_stage_ids.includes(stage.id)
                      ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                      : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
                  "
                  @click="toggleId(form.audience.funnel_stage_ids, stage.id)"
                >
                  {{ stage.name }}
                </button>
              </div>
            </div>
            <p v-if="!funnels.length" class="text-[11px] text-n-slate-10 m-0">
              {{ t('BROADCAST.AUDIENCE.NO_FUNNELS') }}
            </p>
          </div>

          <!-- TODO (out of P3 scope): manual contact selection + phone number
               import (audience.contact_ids / audience.phone_numbers). -->
          <div
            class="flex items-center gap-2 p-3 rounded-xl border border-dashed border-n-weak text-n-slate-10"
          >
            <Icon icon="i-lucide-users" class="size-4" />
            <span class="text-xs">
              {{ t('BROADCAST.AUDIENCE.MANUAL_SOON') }}
            </span>
          </div>
        </section>

        <!-- Throttle -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.THROTTLE_TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11 m-0">
            {{ t('BROADCAST.THROTTLE.HINT') }}
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <label
              v-for="field in [
                'batch_min',
                'batch_max',
                'delay_min',
                'delay_max',
                'daily_cap',
              ]"
              :key="field"
              class="flex flex-col gap-1.5"
            >
              <span class="text-xs font-medium text-n-slate-11">
                {{ t(`BROADCAST.THROTTLE.${field.toUpperCase()}`) }}
              </span>
              <input
                v-model.number="form.throttle[field]"
                type="number"
                min="0"
                class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
              />
            </label>
          </div>
        </section>

        <!-- Schedule -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.SCHEDULE_TITLE') }}
          </h2>
          <label class="flex flex-col gap-1.5 max-w-xs">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('BROADCAST.SCHEDULE.AT') }}
            </span>
            <input
              v-model="form.scheduled_at"
              type="datetime-local"
              class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
            />
            <p class="text-[11px] text-n-slate-10 m-0">
              {{ t('BROADCAST.SCHEDULE.HINT') }}
            </p>
          </label>
        </section>
      </div>

      <!-- Right rail: audience + send controls -->
      <aside
        class="flex flex-col gap-4 px-6 py-6 border-t xl:border-t-0 xl:border-l border-n-weak bg-n-solid-1 overflow-auto"
      >
        <div
          class="flex flex-col gap-2 p-4 rounded-2xl bg-n-alpha-1 border border-n-weak"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('BROADCAST.COMPOSER.AUDIENCE_PREVIEW') }}
          </span>
          <div class="flex items-baseline gap-2">
            <span class="text-3xl font-semibold text-n-slate-12 tabular-nums">
              {{ audienceCount === null ? '—' : audienceCount }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t('BROADCAST.COMPOSER.CONTACTS') }}
            </span>
          </div>
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-refresh-cw"
            :label="t('BROADCAST.COMPOSER.REFRESH_AUDIENCE')"
            :is-loading="isPreviewing"
            @click="refreshAudience"
          />
        </div>

        <div v-if="broadcast" class="grid grid-cols-3 gap-2 text-center">
          <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-alpha-1">
            <span class="text-lg font-semibold text-n-slate-12 tabular-nums">
              {{ broadcast.recipients_count || 0 }}
            </span>
            <span class="text-[11px] text-n-slate-11">
              {{ t('BROADCAST.COMPOSER.STAT_TOTAL') }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-teal-3">
            <span class="text-lg font-semibold text-n-teal-11 tabular-nums">
              {{ broadcast.sent_count || 0 }}
            </span>
            <span class="text-[11px] text-n-teal-11">
              {{ t('BROADCAST.COMPOSER.STAT_SENT') }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-ruby-3">
            <span class="text-lg font-semibold text-n-ruby-11 tabular-nums">
              {{ broadcast.failed_count || 0 }}
            </span>
            <span class="text-[11px] text-n-ruby-11">
              {{ t('BROADCAST.COMPOSER.STAT_FAILED') }}
            </span>
          </div>
        </div>

        <div class="flex flex-col gap-2 mt-auto">
          <Button
            class="w-full"
            variant="outline"
            color="slate"
            icon="i-lucide-save"
            :label="t('BROADCAST.COMPOSER.SAVE')"
            :is-loading="uiFlags.isUpdating"
            @click="save"
          />
          <Button
            v-if="!isRunning"
            class="w-full"
            icon="i-lucide-send"
            :label="t('BROADCAST.COMPOSER.LAUNCH')"
            :disabled="!canLaunch"
            @click="launch"
          />
          <Button
            v-else
            class="w-full"
            color="ruby"
            icon="i-lucide-pause"
            :label="t('BROADCAST.COMPOSER.PAUSE')"
            @click="pause"
          />
        </div>
      </aside>
    </div>
  </div>
</template>
