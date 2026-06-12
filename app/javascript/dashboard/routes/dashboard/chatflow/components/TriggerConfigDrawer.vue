<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import Button from 'dashboard/components-next/button/Button.vue';

// Configures WHEN a flow fires — the single most important part of a chatbot.
// Trigger config lives on the Chatflow itself (inbox_id, trigger_type,
// trigger_config.keywords), persisted through chatflows/update.
const props = defineProps({
  chatflow: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

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
];

const inboxId = ref(null);
const triggerType = ref('on_first_message');
const keywords = ref([]);
const keywordDraft = ref('');

watch(
  () => props.chatflow,
  flow => {
    inboxId.value = flow.inbox_id || null;
    triggerType.value = flow.trigger_type || 'on_first_message';
    keywords.value = Array.isArray(flow.trigger_config?.keywords)
      ? [...flow.trigger_config.keywords]
      : [];
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
    trigger_config: { keywords: keywords.value },
  });
};
</script>

<template>
  <aside
    class="flex flex-col w-[380px] h-full bg-n-solid-1 border-l border-n-weak shadow-xl"
  >
    <header
      class="flex items-center justify-between px-4 h-14 border-b border-n-weak"
    >
      <div class="flex items-center gap-2">
        <span
          class="flex items-center justify-center size-7 rounded-lg bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white"
        >
          <fluent-icon icon="flash" size="15" />
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
            <fluent-icon :icon="type.icon.replace('i-lucide-', '')" size="16" />
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
              <fluent-icon icon="dismiss" size="10" />
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
