<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();

const assistants = ref([]);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const success = ref('');

const selectedAssistantId = ref(null);
const selectedMode = ref('off');

const MODES = [
  {
    key: 'off',
    icon: 'i-lucide-power-off',
    title: 'OFF',
    description: 'IA desativada neste canal',
  },
  {
    key: 'suggest',
    icon: 'i-lucide-message-square-heart',
    title: 'SUGERIR',
    description: 'Agente humano vê sugestões antes de enviar',
  },
  {
    key: 'autopilot',
    icon: 'i-lucide-zap',
    title: 'AUTOPILOTO',
    description: 'IA responde sozinha quando uma mensagem chega',
  },
];

const fetchAssistants = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAssistantsAPI.get();
    assistants.value = data?.payload || data || [];
  } catch (e) {
    error.value =
      e?.response?.data?.message || e?.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const syncFromInbox = () => {
  selectedAssistantId.value = props.inbox.ai_assistant_id || null;
  selectedMode.value = props.inbox.ai_mode || 'off';
};

watch(() => props.inbox, syncFromInbox, { immediate: true });

const hasChanges = computed(() => {
  return (
    selectedAssistantId.value !== (props.inbox.ai_assistant_id || null) ||
    selectedMode.value !== (props.inbox.ai_mode || 'off')
  );
});

const save = async () => {
  saving.value = true;
  error.value = '';
  success.value = '';
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      ai_assistant_id: selectedAssistantId.value,
      ai_mode: selectedMode.value,
    });
    success.value = t('INBOX_MGMT.SETTINGS_POPUP.UPDATE_SUCCESS');
    useAlert(success.value);
    setTimeout(() => {
      success.value = '';
    }, 3000);
  } catch (e) {
    error.value =
      e?.response?.data?.message || e?.response?.data?.error || e.message;
  } finally {
    saving.value = false;
  }
};

onMounted(fetchAssistants);
</script>

<template>
  <div class="flex flex-col gap-6 py-6">
    <header class="flex flex-col gap-1">
      <h2 class="text-lg font-semibold text-n-slate-12 tracking-tight">
        {{ t('INBOX_MGMT.ATHENAS_AI.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11 leading-relaxed">
        {{ t('INBOX_MGMT.ATHENAS_AI.SUBTITLE') }}
      </p>
    </header>

    <section
      v-if="loading"
      class="flex items-center justify-center py-10 rounded-2xl bg-n-alpha-1 ring-1 ring-n-weak"
    >
      <span
        class="i-lucide-loader-circle size-5 animate-spin text-n-slate-10"
      />
    </section>

    <section
      v-else-if="!assistants.length"
      class="flex flex-col items-center gap-3 p-10 rounded-2xl bg-n-alpha-1 ring-1 ring-n-weak text-center"
    >
      <span
        class="size-12 rounded-2xl bg-gradient-to-br from-n-brand/20 to-n-brand/[0.04] ring-1 ring-n-weak grid place-content-center"
      >
        <span class="i-lucide-brain-circuit size-6 text-n-brand" />
      </span>
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('INBOX_MGMT.ATHENAS_AI.EMPTY_TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11 max-w-md leading-relaxed">
        {{ t('INBOX_MGMT.ATHENAS_AI.EMPTY_HINT') }}
      </p>
    </section>

    <template v-else>
      <article
        class="flex flex-col gap-4 p-6 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <header class="flex flex-col gap-1">
          <h3 class="text-sm font-semibold text-n-slate-12 tracking-tight">
            {{ t('INBOX_MGMT.ATHENAS_AI.ASSISTANT_TITLE') }}
          </h3>
          <p class="text-[12px] text-n-slate-11">
            {{ t('INBOX_MGMT.ATHENAS_AI.ASSISTANT_HINT') }}
          </p>
        </header>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <button
            type="button"
            class="flex items-center gap-3 p-3 rounded-xl ring-1 transition-all text-left"
            :class="
              selectedAssistantId === null
                ? 'ring-n-brand bg-n-brand/[0.06]'
                : 'ring-n-weak hover:ring-n-slate-7'
            "
            @click="selectedAssistantId = null"
          >
            <span
              class="size-9 rounded-lg bg-n-alpha-2 grid place-content-center"
            >
              <span class="i-lucide-power-off size-4 text-n-slate-10" />
            </span>
            <span class="flex flex-col gap-0 min-w-0">
              <span class="text-[13px] font-semibold text-n-slate-12">
                {{ t('INBOX_MGMT.ATHENAS_AI.NO_ASSISTANT') }}
              </span>
              <span class="text-[11px] text-n-slate-11">
                {{ t('INBOX_MGMT.ATHENAS_AI.NO_ASSISTANT_HINT') }}
              </span>
            </span>
          </button>
          <button
            v-for="a in assistants"
            :key="a.id"
            type="button"
            class="flex items-center gap-3 p-3 rounded-xl ring-1 transition-all text-left"
            :class="
              selectedAssistantId === a.id
                ? 'ring-n-brand bg-n-brand/[0.06]'
                : 'ring-n-weak hover:ring-n-slate-7'
            "
            @click="selectedAssistantId = a.id"
          >
            <span
              v-if="a.avatar_url"
              class="size-9 rounded-lg bg-cover bg-center ring-1 ring-n-weak"
              :style="{ backgroundImage: `url(${a.avatar_url})` }"
            />
            <span
              v-else
              class="size-9 rounded-lg bg-gradient-to-br from-n-brand to-n-teal-9 grid place-content-center"
            >
              <span class="i-lucide-bot size-4 text-white" />
            </span>
            <span class="flex flex-col gap-0 min-w-0 flex-1">
              <span class="text-[13px] font-semibold text-n-slate-12 truncate">
                {{ a.name }}
              </span>
              <span class="text-[11px] text-n-slate-11 truncate">
                {{ a.role }}
              </span>
            </span>
            <span
              v-if="a.autopilot_enabled"
              class="px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider bg-n-teal-3 text-n-teal-11 ring-1 ring-inset ring-n-teal-6"
            >
              {{ t('INBOX_MGMT.ATHENAS_AI.AUTOPILOT_BADGE') }}
            </span>
          </button>
        </div>
      </article>

      <article
        v-if="selectedAssistantId"
        class="flex flex-col gap-4 p-6 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <header class="flex flex-col gap-1">
          <h3 class="text-sm font-semibold text-n-slate-12 tracking-tight">
            {{ t('INBOX_MGMT.ATHENAS_AI.MODE_TITLE') }}
          </h3>
          <p class="text-[12px] text-n-slate-11">
            {{ t('INBOX_MGMT.ATHENAS_AI.MODE_HINT') }}
          </p>
        </header>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
          <button
            v-for="m in MODES"
            :key="m.key"
            type="button"
            class="flex flex-col gap-2 p-4 rounded-xl ring-1 transition-all text-left"
            :class="
              selectedMode === m.key
                ? 'ring-n-brand bg-n-brand/[0.06]'
                : 'ring-n-weak hover:ring-n-slate-7'
            "
            @click="selectedMode = m.key"
          >
            <span
              class="size-8 rounded-lg grid place-content-center"
              :class="
                selectedMode === m.key
                  ? 'bg-n-brand/15 text-n-brand'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              <span :class="m.icon" class="size-4" />
            </span>
            <span
              class="text-[11px] font-bold uppercase tracking-wider text-n-slate-12"
            >
              {{ m.title }}
            </span>
            <span class="text-[11px] text-n-slate-11 leading-snug">
              {{ m.description }}
            </span>
          </button>
        </div>
      </article>

      <p
        v-if="error"
        class="text-[12px] text-n-ruby-11 bg-n-ruby-3 px-3 py-2 rounded-md ring-1 ring-inset ring-n-ruby-6"
      >
        {{ error }}
      </p>
      <p
        v-if="success"
        class="text-[12px] text-n-teal-11 bg-n-teal-3 px-3 py-2 rounded-md ring-1 ring-inset ring-n-teal-6"
      >
        {{ success }}
      </p>

      <footer class="flex items-center justify-end gap-2">
        <Button
          icon="i-lucide-save"
          :label="t('INBOX_MGMT.ATHENAS_AI.SAVE')"
          :disabled="!hasChanges || saving"
          :is-loading="saving"
          @click="save"
        />
      </footer>
    </template>
  </div>
</template>
