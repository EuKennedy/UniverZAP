<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// Configures WHEN a flow fires — the single most important part of a chatbot.
// Trigger config lives on the Chatflow itself (inbox_id, trigger_type,
// trigger_config.keywords), persisted through chatflows/update.
const props = defineProps({
  chatflow: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
  // Listas e disparos para os gatilhos novos (GET chatflows/options).
  options: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['save', 'close']);

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const accountId = useMapGetter('getCurrentAccountId');

const runUrl = computed(
  () => `/api/v1/accounts/${accountId.value}/chatflows/${props.chatflow.id}/run`
);

// Only message channels can host a WhatsApp-style flow.
const eligibleInboxes = computed(() =>
  inboxes.value.filter(i =>
    ['Channel::Api', 'Channel::Whatsapp'].includes(i.channel_type)
  )
);

const TRIGGER_TYPES = [
  { value: 'on_first_message', icon: 'i-lucide-message-circle-plus' },
  { value: 'keyword', icon: 'i-lucide-hash' },
  { value: 'any_message', icon: 'i-lucide-messages-square' },
  { value: 'webhook', icon: 'i-lucide-webhook' },
  { value: 'ad_referral', icon: 'i-lucide-megaphone' },
  { value: 'recurring_customer', icon: 'i-lucide-repeat' },
  { value: 'no_reply', icon: 'i-lucide-timer' },
  { value: 'label_added', icon: 'i-lucide-tag' },
  { value: 'broadcast_reply', icon: 'i-lucide-reply' },
  { value: 'date', icon: 'i-lucide-calendar-heart' },
  { value: 'list_entered', icon: 'i-lucide-list-plus' },
];

const RESTART_MODES = ['once', 'cooldown'];
const DATE_KINDS = [
  'birthday',
  'after_appointment',
  'after_stage',
  'after_resolution',
];

const labelIds = ref([]);
const broadcastIds = ref([]);
const listIds = ref([]);
const dateConfig = ref({});
const pauseOnAgentReply = ref(true);

const toggleIn = (list, id) =>
  list.includes(id) ? list.filter(v => v !== id) : [...list, id];

const inboxId = ref(null);
const triggerType = ref('on_first_message');
const keywords = ref([]);
const keywordDraft = ref('');
const noReplyMinutes = ref(15);
const restartMode = ref('once');
const restartHours = ref(24);
const senderName = ref('');

watch(
  () => props.chatflow,
  flow => {
    inboxId.value = flow.inbox_id || null;
    triggerType.value = flow.trigger_type || 'on_first_message';
    noReplyMinutes.value = Number(flow.trigger_config?.no_reply_minutes) || 15;
    keywords.value = Array.isArray(flow.trigger_config?.keywords)
      ? [...flow.trigger_config.keywords]
      : [];
    restartMode.value = flow.trigger_config?.restart?.mode || 'once';
    restartHours.value = flow.trigger_config?.restart?.hours || 24;
    senderName.value = flow.trigger_config?.sender_name || '';
    labelIds.value = [...(flow.trigger_config?.label_ids || [])];
    broadcastIds.value = [...(flow.trigger_config?.broadcast_ids || [])];
    listIds.value = [...(flow.trigger_config?.list_ids || [])];
    dateConfig.value = {
      kind: 'birthday',
      attribute_key: 'data_nascimento',
      days: 1,
      hour: 10,
      ...(flow.trigger_config?.date || {}),
    };
    pauseOnAgentReply.value =
      flow.trigger_config?.pause_on_agent_reply !== false;
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('inboxes/get');
});

const addKeyword = () => {
  const parts = keywordDraft.value
    .split(',')
    .map(k => k.trim().toLowerCase())
    .filter(k => k && !keywords.value.includes(k));
  if (parts.length) keywords.value = [...keywords.value, ...parts];
  keywordDraft.value = '';
};

const removeKeyword = index => {
  keywords.value = keywords.value.filter((_, i) => i !== index);
};

const save = () => {
  emit('save', {
    inbox_id: inboxId.value,
    trigger_type: triggerType.value,
    trigger_config: {
      // A posição do balão do gatilho viaja junto: ela mora aqui e um save que
      // não a reenviasse jogaria o balão de volta para o canto na próxima
      // abertura.
      ...(props.chatflow.trigger_config || {}),
      keywords: keywords.value,
      no_reply_minutes: Number(noReplyMinutes.value) || 15,
      restart: { mode: restartMode.value, hours: Number(restartHours.value) },
      sender_name: senderName.value.trim(),
      label_ids: labelIds.value,
      broadcast_ids: broadcastIds.value,
      list_ids: listIds.value,
      date: {
        ...dateConfig.value,
        days: Number(dateConfig.value.days) || 0,
        hour: Number(dateConfig.value.hour) || 0,
      },
      pause_on_agent_reply: pauseOnAgentReply.value,
    },
  });
};
</script>

<template>
  <aside
    class="flex flex-col w-[380px] h-full bg-n-solid-1 border-r border-n-weak shadow-xl"
  >
    <header
      class="flex items-center justify-between px-4 h-14 border-b border-n-weak"
    >
      <div class="flex items-center gap-2">
        <span
          class="flex items-center justify-center size-7 rounded-lg bg-gradient-to-br from-n-teal-8 to-n-teal-9 text-white"
        >
          <Icon icon="i-lucide-zap" class="size-3.5" />
        </span>
        <h3 class="text-sm font-semibold text-n-slate-12 m-0">
          {{ t('CHATFLOW.TRIGGER.TITLE') }}
        </h3>
      </div>
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-x"
        @click="emit('close')"
      />
    </header>

    <div class="flex-1 overflow-auto px-4 py-4 flex flex-col gap-5">
      <p class="text-xs text-n-slate-11 m-0 leading-relaxed">
        {{ t('CHATFLOW.TRIGGER.SUBTITLE') }}
      </p>

      <!-- Inbox -->
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.INBOX') }}
        </span>
        <select
          v-model="inboxId"
          class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
        >
          <option :value="null">{{ t('CHATFLOW.TRIGGER.ALL_INBOXES') }}</option>
          <option
            v-for="inbox in eligibleInboxes"
            :key="inbox.id"
            :value="inbox.id"
          >
            {{ inbox.name }}
          </option>
        </select>
      </label>

      <!-- Trigger type -->
      <div class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.WHEN') }}
        </span>
        <button
          v-for="type in TRIGGER_TYPES"
          :key="type.value"
          type="button"
          class="flex items-start gap-3 p-3 rounded-xl border text-left cursor-pointer transition-all"
          :class="
            triggerType === type.value
              ? 'border-n-teal-8 bg-n-teal-3/50 ring-1 ring-n-teal-7/40'
              : 'border-n-weak hover:border-n-slate-6'
          "
          @click="triggerType = type.value"
        >
          <span
            class="flex items-center justify-center size-8 rounded-lg shrink-0"
            :class="
              triggerType === type.value
                ? 'bg-n-teal-9 text-white'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            <Icon :icon="type.icon" class="size-4" />
          </span>
          <span class="flex flex-col gap-0.5 min-w-0">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`CHATFLOW.TRIGGER.TYPE.${type.value.toUpperCase()}.LABEL`) }}
            </span>
            <span class="text-xs text-n-slate-11 leading-snug">
              {{ t(`CHATFLOW.TRIGGER.TYPE.${type.value.toUpperCase()}.HINT`) }}
            </span>
          </span>
        </button>
      </div>

      <!-- O nome que assina as mensagens deste fluxo. O Chatwoot assina com o
        nome de QUEM escreveu, e mensagem de fluxo não tem autor humano: a
        assinatura saía vazia e o cliente recebia os asteriscos do negrito com
        nada no meio. -->
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.SENDER_NAME') }}
        </span>
        <input
          v-model="senderName"
          type="text"
          :placeholder="t('CHATFLOW.TRIGGER.SENDER_NAME_PLACEHOLDER')"
          data-testid="trigger-sender-name"
          class="px-3 h-9 text-sm rounded-lg border bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus:border-n-teal-8"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('CHATFLOW.TRIGGER.SENDER_NAME_HINT') }}
        </span>
      </label>

      <!-- Keywords (only for keyword trigger) -->
      <div v-if="triggerType === 'keyword'" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.KEYWORDS') }}
        </span>
        <div
          class="flex flex-wrap items-center gap-1.5 p-2 rounded-lg bg-n-alpha-1 border border-n-weak min-h-10"
        >
          <span
            v-for="(kw, index) in keywords"
            :key="kw"
            class="inline-flex items-center gap-1 pl-2 pr-1 py-0.5 rounded-md bg-n-teal-3 text-n-teal-12 text-xs font-medium"
          >
            {{ kw }}
            <button
              type="button"
              class="inline-flex items-center justify-center size-4 rounded hover:bg-n-teal-5 cursor-pointer"
              @click="removeKeyword(index)"
            >
              <Icon icon="i-lucide-x" class="size-2.5" />
            </button>
          </span>
          <input
            v-model="keywordDraft"
            type="text"
            :placeholder="t('CHATFLOW.TRIGGER.KEYWORD_PLACEHOLDER')"
            class="flex-1 min-w-24 bg-transparent text-sm text-n-slate-12 focus:outline-none"
            @keydown.enter.prevent="addKeyword"
            @blur="addKeyword"
          />
        </div>
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.TRIGGER.KEYWORD_HINT') }}
        </p>
      </div>

      <!-- Minutes without a human reply (no_reply trigger) -->
      <div v-if="triggerType === 'no_reply'" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.NO_REPLY_MINUTES') }}
        </span>
        <input
          v-model="noReplyMinutes"
          type="number"
          min="1"
          class="h-10 w-32 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
        />
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.TRIGGER.NO_REPLY_HINT') }}
        </p>
      </div>

      <!-- Restart rule (first-message trigger) -->
      <div
        v-if="triggerType === 'on_first_message'"
        class="flex flex-col gap-2"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.RESTART') }}
        </span>
        <select
          v-model="restartMode"
          class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
        >
          <option v-for="m in RESTART_MODES" :key="m" :value="m">
            {{ t(`CHATFLOW.TRIGGER.RESTART_MODE.${m.toUpperCase()}`) }}
          </option>
        </select>
        <label
          v-if="restartMode === 'cooldown'"
          class="flex items-center gap-2"
        >
          <span class="text-xs text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.RESTART_EVERY') }}
          </span>
          <input
            v-model.number="restartHours"
            type="number"
            min="1"
            class="w-20 h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.RESTART_HOURS') }}
          </span>
        </label>
      </div>

      <!-- Etiqueta adicionada -->
      <div v-if="triggerType === 'label_added'" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.LABELS') }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="label in labels"
            :key="label.id"
            type="button"
            class="flex items-center gap-1.5 px-2.5 h-8 rounded-lg border text-xs cursor-pointer transition-colors"
            :class="
              labelIds.includes(label.id)
                ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
            "
            :data-testid="`trigger-label-${label.id}`"
            @click="labelIds = toggleIn(labelIds, label.id)"
          >
            <span
              class="size-2 rounded-full"
              :style="{ backgroundColor: label.color }"
            />
            {{ label.title }}
          </button>
        </div>
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.TRIGGER.LABELS_HINT') }}
        </p>
      </div>

      <!-- Respondeu a um disparo -->
      <div v-if="triggerType === 'broadcast_reply'" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.BROADCASTS') }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="broadcast in options.broadcasts || []"
            :key="broadcast.id"
            type="button"
            class="flex items-center gap-1.5 px-2.5 h-8 rounded-lg border text-xs cursor-pointer transition-colors"
            :class="
              broadcastIds.includes(broadcast.id)
                ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
            "
            @click="broadcastIds = toggleIn(broadcastIds, broadcast.id)"
          >
            {{ broadcast.name }}
          </button>
        </div>
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.TRIGGER.BROADCASTS_HINT') }}
        </p>
      </div>

      <!-- Data -->
      <div
        v-if="triggerType === 'date'"
        class="flex flex-col gap-3"
        data-testid="trigger-date"
      >
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.DATE_KIND') }}
          </span>
          <select
            v-model="dateConfig.kind"
            class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option v-for="kind in DATE_KINDS" :key="kind" :value="kind">
              {{ t(`CHATFLOW.TRIGGER.DATE_KINDS.${kind.toUpperCase()}`) }}
            </option>
          </select>
        </label>
        <label
          v-if="dateConfig.kind === 'birthday'"
          class="flex flex-col gap-1.5"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.DATE_ATTRIBUTE') }}
          </span>
          <input
            v-model="dateConfig.attribute_key"
            type="text"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
        </label>
        <label v-else class="flex items-center gap-2">
          <input
            v-model.number="dateConfig.days"
            type="number"
            min="0"
            class="w-20 h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.DATE_DAYS_AFTER') }}
          </span>
        </label>
        <label
          v-if="dateConfig.kind === 'after_stage'"
          class="flex flex-col gap-1.5"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.DATE_STAGE') }}
          </span>
          <select
            v-model="dateConfig.label_id"
            class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option v-for="label in labels" :key="label.id" :value="label.id">
              {{ label.title }}
            </option>
          </select>
        </label>
        <label class="flex items-center gap-2">
          <span class="text-xs text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.DATE_HOUR') }}
          </span>
          <input
            v-model.number="dateConfig.hour"
            type="number"
            min="0"
            max="23"
            class="w-20 h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
        </label>
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.TRIGGER.DATE_HINT') }}
        </p>
      </div>

      <!-- Entrou numa lista -->
      <div v-if="triggerType === 'list_entered'" class="flex flex-col gap-2">
        <p
          v-if="!options.lists_available"
          class="p-3 rounded-xl bg-n-amber-3 text-n-amber-11 text-xs m-0"
          data-testid="trigger-lists-unavailable"
        >
          {{ t('CHATFLOW.EDITOR.LIST.UNAVAILABLE') }}
        </p>
        <template v-else>
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CHATFLOW.TRIGGER.LISTS') }}
          </span>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="list in options.lists || []"
              :key="list.id"
              type="button"
              class="flex items-center gap-1.5 px-2.5 h-8 rounded-lg border text-xs cursor-pointer transition-colors"
              :class="
                listIds.includes(list.id)
                  ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-12'
                  : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
              "
              @click="listIds = toggleIn(listIds, list.id)"
            >
              {{ list.name }}
            </button>
          </div>
        </template>
      </div>

      <!-- Pausar o robô quando um atendente responde -->
      <label
        class="flex items-start gap-2 p-3 rounded-xl border border-n-weak cursor-pointer"
      >
        <input
          v-model="pauseOnAgentReply"
          type="checkbox"
          class="mt-0.5 accent-n-teal-9"
          data-testid="trigger-pause-on-agent"
        />
        <span class="flex flex-col gap-0.5">
          <span class="text-sm text-n-slate-12">
            {{ t('CHATFLOW.TRIGGER.PAUSE_ON_AGENT') }}
          </span>
          <span class="text-[11px] text-n-slate-10">
            {{ t('CHATFLOW.TRIGGER.PAUSE_ON_AGENT_HINT') }}
          </span>
        </span>
      </label>

      <!-- Webhook trigger: external start URL -->
      <div v-if="triggerType === 'webhook'" class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CHATFLOW.TRIGGER.RUN_URL') }}
        </span>
        <input
          :value="runUrl"
          readonly
          class="h-10 px-3 rounded-lg bg-n-alpha-2 border border-n-weak text-xs text-n-slate-11 focus:outline-none"
          @focus="$event.target.select()"
        />
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.TRIGGER.RUN_HINT') }}
        </p>
      </div>
    </div>

    <footer class="flex items-center gap-2 px-4 py-3 border-t border-n-weak">
      <Button
        class="flex-1"
        :label="t('CHATFLOW.TRIGGER.SAVE')"
        :is-loading="isSaving"
        @click="save"
      />
    </footer>
  </aside>
</template>
