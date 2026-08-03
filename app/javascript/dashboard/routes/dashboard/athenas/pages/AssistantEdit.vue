<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import AthenasAssistantsAPI from 'dashboard/api/athenas';
import {
  TONE_OPTIONS,
  TRAINING_CATEGORY_OPTIONS,
} from 'dashboard/routes/dashboard/athenas/constants';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AthenasPlayground from 'dashboard/components-next/athenas/AthenasPlayground.vue';
import AthenasAnalytics from 'dashboard/components-next/athenas/AthenasAnalytics.vue';
import AthenasReviewQueue from 'dashboard/components-next/athenas/AthenasReviewQueue.vue';
import AthenasPromptLab from 'dashboard/components-next/athenas/AthenasPromptLab.vue';
import AthenasRadar from 'dashboard/components-next/athenas/AthenasRadar.vue';

const props = defineProps({ id: { type: Number, required: true } });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const assistant = ref(null);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const success = ref('');

const form = reactive({
  name: '',
  role: '',
  description: '',
  avatar_url: '',
  tone: 'sales',
  model: 'claude-sonnet-4-5',
  system_prompt: '',
  temperature: 0.3,
  max_tokens: 1024,
  autopilot_enabled: false,
  active: true,
  encrypted_anthropic_key: '',
  guardrails: { stop_words: [], max_messages_per_minute: 4 },
});

const TABS = [
  { key: 'general', icon: 'i-lucide-user-circle-2' },
  { key: 'knowledge', icon: 'i-lucide-book-open' },
  // Right after knowledge on purpose: you feed the agent, then you test it.
  { key: 'test', icon: 'i-lucide-message-circle' },
  { key: 'activity', icon: 'i-lucide-activity' },
  // Separate from activity because they answer different questions. Activity is
  // "how is it doing"; review is "what do I have to fix", and mixing a work
  // queue into a dashboard turns both into neither.
  { key: 'review', icon: 'i-lucide-shield-check' },
  // Last because it is the only tab that changes how the agent behaves for
  // everyone, and it is the one you reach after the other five taught you what
  // to change.
  { key: 'lab', icon: 'i-lucide-flask-conical' },
  // The commercial answer: everything else says whether the agent is good,
  // this says whether it is worth paying for.
  { key: 'radar', icon: 'i-lucide-radar' },
];

const currentTab = ref('general');
// Advanced tuning is collapsed: it is set once, unlike name/tone/prompt.
const advancedOpen = ref(false);

const MODELS = [
  {
    key: 'claude-sonnet-4-5',
    title: 'Sonnet 4.5',
    description: 'Equilíbrio entre custo e qualidade.',
    badge: 'Recomendado',
  },
  {
    key: 'claude-opus-4-5',
    title: 'Opus 4.5',
    description: 'Máxima qualidade.',
    badge: 'Premium',
  },
  {
    key: 'claude-haiku-4-5',
    title: 'Haiku 4.5',
    description: 'Mais barato e rápido.',
    badge: 'Eco',
  },
];

const tones = computed(() =>
  TONE_OPTIONS.map(o => ({ ...o, label: t(o.labelKey) }))
);

const stopWordsCSV = computed({
  get: () => (form.guardrails.stop_words || []).join(', '),
  set: v => {
    form.guardrails.stop_words = v
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
  },
});

const fetchAssistant = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAssistantsAPI.show(props.id);
    assistant.value = data;
    Object.assign(form, {
      name: data.name,
      role: data.role,
      description: data.description || '',
      avatar_url: data.avatar_url || '',
      tone: data.tone,
      model: data.model,
      system_prompt: data.system_prompt || '',
      temperature: data.temperature,
      max_tokens: data.max_tokens,
      autopilot_enabled: data.autopilot_enabled,
      active: data.active,
      encrypted_anthropic_key: '',
      guardrails: data.guardrails || {
        stop_words: [],
        max_messages_per_minute: 4,
      },
    });
  } catch (e) {
    error.value =
      e?.response?.data?.message || e?.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const save = async () => {
  saving.value = true;
  error.value = '';
  success.value = '';
  try {
    const payload = { ...form };
    if (!payload.encrypted_anthropic_key)
      delete payload.encrypted_anthropic_key;
    const { data } = await AthenasAssistantsAPI.update(props.id, {
      ai_assistant: payload,
    });
    assistant.value = data;
    success.value = t('ATHENAS.EDIT.SAVE_SUCCESS');
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

const goBack = () =>
  router.push(accountScopedRoute('athenas_assistants_index'));

const confirmDialogRef = ref(null);
const confirmState = ref({ title: '', description: '', onConfirm: null });
const askConfirmation = ({ title, description, onConfirm }) => {
  confirmState.value = { title, description, onConfirm };
  confirmDialogRef.value?.open();
};
const runConfirmedAction = async () => {
  const action = confirmState.value.onConfirm;
  confirmDialogRef.value?.close();
  if (action) await action();
};

const performRemove = async () => {
  try {
    await AthenasAssistantsAPI.delete(props.id);
    useAlert(t('ATHENAS.EDIT.DELETE_SUCCESS'));
    goBack();
  } catch (e) {
    useAlert(
      e?.response?.data?.message || e?.response?.data?.error || e.message
    );
  }
};

const remove = () =>
  askConfirmation({
    title: t('ATHENAS.EDIT.DELETE_TITLE'),
    description: t('ATHENAS.EDIT.DELETE_CONFIRM'),
    onConfirm: performRemove,
  });

const toggleAutopilot = () => {
  form.autopilot_enabled = !form.autopilot_enabled;
};

// === Knowledge base (trainings) ===
const trainingCategories = computed(() =>
  TRAINING_CATEGORY_OPTIONS.map(o => ({ key: o.key, label: t(o.labelKey) }))
);

const trainings = ref([]);
const trainingsLoading = ref(false);
const editorOpen = ref(false);
const savingTraining = ref(false);
const trainingForm = reactive({
  id: null,
  title: '',
  category: 'base',
  source_type: 'text',
  content: '',
});

const categoryLabel = key =>
  trainingCategories.value.find(c => c.key === key)?.label || key;

const trainingMeta = tr =>
  `${categoryLabel(tr.category)} · ${tr.char_count ?? 0} · ${tr.status}`;

const fetchTrainings = async () => {
  trainingsLoading.value = true;
  try {
    const { data } = await AthenasAssistantsAPI.listTrainings(props.id);
    trainings.value = data?.payload || [];
  } catch (e) {
    useAlert(
      e?.response?.data?.message || e?.response?.data?.error || e.message
    );
  } finally {
    trainingsLoading.value = false;
  }
};

const openNewTraining = () => {
  Object.assign(trainingForm, {
    id: null,
    title: '',
    category: 'base',
    source_type: 'text',
    content: '',
  });
  editorOpen.value = true;
};

const openEditTraining = training => {
  Object.assign(trainingForm, {
    id: training.id,
    title: training.title,
    category: training.category || 'base',
    source_type: training.source_type || 'text',
    content: training.content || '',
  });
  editorOpen.value = true;
};

const closeEditor = () => {
  editorOpen.value = false;
};

const saveTraining = async () => {
  if (!trainingForm.title || !trainingForm.content) return;
  savingTraining.value = true;
  try {
    const payload = {
      title: trainingForm.title,
      category: trainingForm.category,
      source_type: trainingForm.source_type,
      content: trainingForm.content,
    };
    if (trainingForm.id) {
      await AthenasAssistantsAPI.updateTraining(
        props.id,
        trainingForm.id,
        payload
      );
    } else {
      await AthenasAssistantsAPI.createTraining(props.id, payload);
    }
    useAlert(t('ATHENAS.EDIT.KNOWLEDGE.SAVE_SUCCESS'));
    editorOpen.value = false;
    await fetchTrainings();
  } catch (e) {
    useAlert(
      e?.response?.data?.message || e?.response?.data?.error || e.message
    );
  } finally {
    savingTraining.value = false;
  }
};

const performRemoveTraining = async training => {
  try {
    await AthenasAssistantsAPI.deleteTraining(props.id, training.id);
    useAlert(t('ATHENAS.EDIT.KNOWLEDGE.DELETE_SUCCESS'));
    await fetchTrainings();
  } catch (e) {
    useAlert(
      e?.response?.data?.message || e?.response?.data?.error || e.message
    );
  }
};

const removeTraining = training =>
  askConfirmation({
    title: t('ATHENAS.EDIT.KNOWLEDGE.DELETE_TITLE'),
    description: t('ATHENAS.EDIT.KNOWLEDGE.DELETE_CONFIRM'),
    onConfirm: () => performRemoveTraining(training),
  });

const statusBadge = computed(() => {
  if (!assistant.value) return null;
  if (assistant.value.autopilot_enabled) {
    return {
      cls: 'bg-n-teal-3 text-n-teal-11 ring-n-teal-6',
      label: t('ATHENAS.EDIT.STATUS_AUTOPILOT'),
      icon: 'i-lucide-zap',
    };
  }
  return assistant.value.active
    ? {
        cls: 'bg-n-teal-3 text-n-teal-11 ring-n-teal-6',
        label: t('ATHENAS.EDIT.STATUS_ACTIVE'),
        icon: 'i-lucide-circle-dot',
      }
    : {
        cls: 'bg-n-alpha-2 text-n-slate-11 ring-n-weak',
        label: t('ATHENAS.EDIT.STATUS_INACTIVE'),
        icon: 'i-lucide-circle',
      };
});

watch(
  () => props.id,
  () => {
    fetchAssistant();
    fetchTrainings();
  }
);

onMounted(() => {
  fetchAssistant();
  fetchTrainings();
});
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-5 border-b border-n-weak flex-shrink-0"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          size="xs"
          ghost
          slate
          @click="goBack"
        />
        <span
          v-if="assistant?.avatar_url"
          class="size-10 rounded-xl bg-cover bg-center ring-1 ring-n-weak flex-shrink-0"
          :style="{ backgroundImage: `url(${assistant.avatar_url})` }"
        />
        <span
          v-else
          class="size-10 rounded-xl bg-gradient-to-br from-n-brand to-n-teal-9 grid place-content-center flex-shrink-0"
        >
          <span class="i-lucide-bot size-5 text-white" />
        </span>
        <div class="flex flex-col gap-0.5 min-w-0">
          <h1
            class="text-base font-semibold text-n-slate-12 truncate tracking-tight"
          >
            {{ assistant?.name || t('ATHENAS.EDIT.LOADING') }}
          </h1>
          <p class="text-[11px] text-n-slate-11 truncate">
            {{ assistant?.role }}
          </p>
        </div>
        <span
          v-if="statusBadge"
          class="ml-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] uppercase font-bold tracking-wider ring-1 ring-inset"
          :class="statusBadge.cls"
        >
          <span :class="statusBadge.icon" class="size-3" />
          {{ statusBadge.label }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Button
          v-if="assistant"
          size="sm"
          faded
          ruby
          icon="i-lucide-trash-2"
          :label="t('ATHENAS.EDIT.DELETE')"
          @click="remove"
        />
        <Button
          v-if="assistant"
          size="sm"
          icon="i-lucide-save"
          :label="t('ATHENAS.EDIT.SAVE')"
          :is-loading="saving"
          :disabled="saving"
          @click="save"
        />
      </div>
    </header>

    <nav
      class="flex items-center gap-1 px-8 pt-3 border-b border-n-weak flex-shrink-0"
    >
      <button
        v-for="tab in TABS"
        :key="tab.key"
        type="button"
        class="flex items-center gap-2 px-4 py-2.5 -mb-px text-[13px] font-medium transition-colors border-b-2"
        :class="
          currentTab === tab.key
            ? 'text-n-brand border-n-brand'
            : 'text-n-slate-11 border-transparent hover:text-n-slate-12'
        "
        @click="currentTab = tab.key"
      >
        <span :class="tab.icon" class="size-4" />
        {{ t(`ATHENAS.EDIT.TABS.${tab.key.toUpperCase()}`) }}
      </button>
    </nav>

    <section v-if="loading" class="flex-1 flex items-center justify-center">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <section v-else-if="assistant" class="flex-1 overflow-y-auto px-8 py-6">
      <!-- Left-aligned, NOT centred: the header and the tab bar start at the
           same px-8 gutter, so a centred column here is what made everything
           look adrift on a wide screen. -->
      <div class="w-full max-w-5xl flex flex-col gap-5">
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

        <!-- TAB: GENERAL -->
        <template v-if="currentTab === 'general'">
          <article
            class="flex flex-col gap-5 p-6 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
          >
            <header class="flex flex-col gap-1">
              <h2
                class="text-base font-semibold text-n-slate-12 tracking-tight"
              >
                {{ t('ATHENAS.EDIT.SECTIONS.IDENTITY') }}
              </h2>
              <p class="text-[12px] text-n-slate-11">
                {{ t('ATHENAS.EDIT.SECTIONS.IDENTITY_HINT') }}
              </p>
            </header>
            <Input
              v-model="form.name"
              :label="t('ATHENAS.WIZARD.IDENTITY.NAME_LABEL')"
            />
            <Input
              v-model="form.role"
              :label="t('ATHENAS.WIZARD.IDENTITY.ROLE_LABEL')"
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.IDENTITY.DESCRIPTION_LABEL') }}
              </label>
              <textarea
                v-model="form.description"
                rows="3"
                class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
              />
            </div>
            <Input
              v-model="form.avatar_url"
              :label="t('ATHENAS.WIZARD.IDENTITY.AVATAR_LABEL')"
              :placeholder="t('ATHENAS.WIZARD.IDENTITY.AVATAR_PLACEHOLDER')"
            />
          </article>

          <article
            class="flex flex-col gap-5 p-6 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
          >
            <header class="flex flex-col gap-1">
              <h2
                class="text-base font-semibold text-n-slate-12 tracking-tight"
              >
                {{ t('ATHENAS.EDIT.SECTIONS.PERSONALITY') }}
              </h2>
              <p class="text-[12px] text-n-slate-11">
                {{ t('ATHENAS.EDIT.SECTIONS.PERSONALITY_HINT') }}
              </p>
            </header>

            <div class="flex flex-col gap-2">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.PERSONALITY.TONE_LABEL') }}
              </label>
              <div class="grid grid-cols-3 gap-2 sm:grid-cols-5">
                <button
                  v-for="t2 in tones"
                  :key="t2.key"
                  type="button"
                  class="flex flex-col items-center gap-1.5 p-3 rounded-xl ring-1 transition-all"
                  :class="
                    form.tone === t2.key
                      ? 'ring-n-brand bg-n-brand/10 text-n-slate-12'
                      : 'ring-n-weak text-n-slate-11 hover:ring-n-slate-7'
                  "
                  @click="form.tone = t2.key"
                >
                  <span :class="t2.icon" class="size-5" />
                  <span class="text-[11px] font-medium">{{ t2.label }}</span>
                </button>
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.PERSONALITY.MODEL_LABEL') }}
              </label>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
                <button
                  v-for="m in MODELS"
                  :key="m.key"
                  type="button"
                  class="flex flex-col gap-1 p-3 rounded-xl ring-1 text-left transition-all"
                  :class="
                    form.model === m.key
                      ? 'ring-n-brand bg-n-brand/10'
                      : 'ring-n-weak hover:ring-n-slate-7'
                  "
                  @click="form.model = m.key"
                >
                  <div class="flex items-center justify-between">
                    <span class="text-[13px] font-semibold text-n-slate-12">
                      {{ m.title }}
                    </span>
                    <span
                      class="px-1.5 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider bg-n-alpha-2 text-n-slate-11"
                    >
                      {{ m.badge }}
                    </span>
                  </div>
                  <p class="text-[11px] text-n-slate-11 leading-snug">
                    {{ m.description }}
                  </p>
                </button>
              </div>
            </div>

            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.PERSONALITY.PROMPT_LABEL') }}
              </label>
              <textarea
                v-model="form.system_prompt"
                rows="10"
                class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 font-mono leading-relaxed focus:outline-none focus:border-n-brand resize-y"
              />
            </div>

            <!-- Collapsed by default: name, tone, model and prompt are what an
                 operator actually revisits. Creativity, token cap and the API
                 key are set once, and giving them the same visual weight as
                 the prompt is what made this screen read as a settings dump. -->
            <button
              type="button"
              class="flex items-center gap-1.5 self-start text-[13px] font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors"
              @click="advancedOpen = !advancedOpen"
            >
              <span
                class="size-3.5"
                :class="
                  advancedOpen
                    ? 'i-lucide-chevron-down'
                    : 'i-lucide-chevron-right'
                "
              />
              {{ t('ATHENAS.EDIT.ADVANCED') }}
            </button>

            <template v-if="advancedOpen">
              <div class="grid grid-cols-2 gap-3">
                <div class="flex flex-col gap-1.5">
                  <label class="text-sm font-medium text-n-slate-12">
                    {{ t('ATHENAS.WIZARD.PERSONALITY.TEMPERATURE_LABEL') }}
                    <span class="text-n-slate-11 tabular-nums">
                      ({{ form.temperature.toFixed(2) }})
                    </span>
                  </label>
                  <input
                    v-model.number="form.temperature"
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    class="w-full accent-n-teal-9"
                  />
                </div>
                <div class="flex flex-col gap-1.5">
                  <label class="text-sm font-medium text-n-slate-12">
                    {{ t('ATHENAS.WIZARD.PERSONALITY.MAX_TOKENS_LABEL') }}
                  </label>
                  <Input
                    v-model.number="form.max_tokens"
                    type="number"
                    min="128"
                    max="8192"
                  />
                </div>
              </div>

              <div class="flex flex-col gap-1.5">
                <label class="text-sm font-medium text-n-slate-12">
                  {{ t('ATHENAS.EDIT.REPLACE_API_KEY_LABEL') }}
                </label>
                <Input
                  v-model="form.encrypted_anthropic_key"
                  type="password"
                  :placeholder="t('ATHENAS.EDIT.REPLACE_API_KEY_PLACEHOLDER')"
                />
                <p class="text-[11px] text-n-slate-11">
                  {{ t('ATHENAS.EDIT.REPLACE_API_KEY_HINT') }}
                </p>
              </div>
            </template>
          </article>

          <article
            class="flex flex-col gap-5 p-6 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
          >
            <header class="flex flex-col gap-1">
              <h2
                class="text-base font-semibold text-n-slate-12 tracking-tight"
              >
                {{ t('ATHENAS.EDIT.SECTIONS.BEHAVIOR') }}
              </h2>
              <p class="text-[12px] text-n-slate-11">
                {{ t('ATHENAS.EDIT.SECTIONS.BEHAVIOR_HINT') }}
              </p>
            </header>

            <button
              type="button"
              class="flex items-start gap-3 p-4 rounded-xl ring-1 transition-all text-left"
              :class="
                form.autopilot_enabled
                  ? 'ring-n-brand bg-n-brand/[0.06]'
                  : 'ring-n-weak hover:ring-n-slate-7'
              "
              @click="toggleAutopilot"
            >
              <span
                class="size-5 rounded-md ring-1 mt-0.5 grid place-content-center transition-colors"
                :class="
                  form.autopilot_enabled
                    ? 'ring-n-brand bg-n-brand text-white'
                    : 'ring-n-weak'
                "
              >
                <span
                  v-if="form.autopilot_enabled"
                  class="i-lucide-check size-3.5"
                />
              </span>
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ t('ATHENAS.WIZARD.BEHAVIOR.AUTOPILOT_LABEL') }}
                </span>
                <p class="text-[12px] text-n-slate-11 leading-relaxed">
                  {{ t('ATHENAS.WIZARD.BEHAVIOR.AUTOPILOT_HINT') }}
                </p>
              </div>
            </button>

            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.BEHAVIOR.STOP_WORDS_LABEL') }}
              </label>
              <Input v-model="stopWordsCSV" />
              <p class="text-[11px] text-n-slate-11">
                {{ t('ATHENAS.WIZARD.BEHAVIOR.STOP_WORDS_HINT') }}
              </p>
            </div>

            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.BEHAVIOR.RATE_LIMIT_LABEL') }}
              </label>
              <Input
                v-model.number="form.guardrails.max_messages_per_minute"
                type="number"
                min="1"
                max="60"
              />
            </div>

            <button
              type="button"
              class="flex items-start gap-3 p-4 rounded-xl ring-1 transition-all text-left"
              :class="
                form.active
                  ? 'ring-n-teal-6 bg-n-teal-3/30'
                  : 'ring-n-weak hover:ring-n-slate-7'
              "
              @click="form.active = !form.active"
            >
              <span
                class="size-5 rounded-md ring-1 mt-0.5 grid place-content-center transition-colors"
                :class="
                  form.active
                    ? 'ring-n-teal-6 bg-n-teal-9 text-white'
                    : 'ring-n-weak'
                "
              >
                <span v-if="form.active" class="i-lucide-check size-3.5" />
              </span>
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ t('ATHENAS.EDIT.ACTIVE_LABEL') }}
                </span>
                <p class="text-[12px] text-n-slate-11 leading-relaxed">
                  {{ t('ATHENAS.EDIT.ACTIVE_HINT') }}
                </p>
              </div>
            </button>
          </article>
        </template>

        <!-- TAB: KNOWLEDGE -->
        <template v-if="currentTab === 'knowledge'">
          <div class="flex flex-col gap-4">
            <div class="flex items-center justify-between gap-3">
              <div class="flex flex-col gap-0.5">
                <h2
                  class="text-lg font-semibold text-n-slate-12 tracking-tight"
                >
                  {{ t('ATHENAS.EDIT.KNOWLEDGE.TITLE') }}
                </h2>
                <p class="text-[12px] text-n-slate-11">
                  {{ t('ATHENAS.EDIT.KNOWLEDGE.SUBTITLE') }}
                </p>
              </div>
              <Button
                icon="i-lucide-plus"
                size="sm"
                :label="t('ATHENAS.EDIT.KNOWLEDGE.ADD')"
                @click="openNewTraining"
              />
            </div>

            <article
              v-if="editorOpen"
              class="flex flex-col gap-3 p-5 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
            >
              <div class="flex flex-col gap-1.5">
                <label class="text-sm font-medium text-n-slate-12">
                  {{ t('ATHENAS.EDIT.KNOWLEDGE.FIELD_TITLE') }}
                </label>
                <Input v-model="trainingForm.title" />
              </div>
              <div class="flex flex-col gap-1.5">
                <label class="text-sm font-medium text-n-slate-12">
                  {{ t('ATHENAS.EDIT.KNOWLEDGE.FIELD_CATEGORY') }}
                </label>
                <select
                  v-model="trainingForm.category"
                  class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
                >
                  <option
                    v-for="c in trainingCategories"
                    :key="c.key"
                    :value="c.key"
                  >
                    {{ c.label }}
                  </option>
                </select>
              </div>
              <div class="flex flex-col gap-1.5">
                <label class="text-sm font-medium text-n-slate-12">
                  {{ t('ATHENAS.EDIT.KNOWLEDGE.FIELD_CONTENT') }}
                </label>
                <textarea
                  v-model="trainingForm.content"
                  rows="10"
                  class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 font-mono leading-relaxed focus:outline-none focus:border-n-brand resize-y"
                />
              </div>
              <div class="flex items-center gap-2 justify-end">
                <Button
                  ghost
                  slate
                  size="sm"
                  :label="t('ATHENAS.EDIT.KNOWLEDGE.CANCEL')"
                  @click="closeEditor"
                />
                <Button
                  size="sm"
                  :is-loading="savingTraining"
                  :disabled="
                    savingTraining ||
                    !trainingForm.title ||
                    !trainingForm.content
                  "
                  :label="t('ATHENAS.EDIT.KNOWLEDGE.SAVE')"
                  @click="saveTraining"
                />
              </div>
            </article>

            <p v-if="trainingsLoading" class="text-sm text-n-slate-11">
              {{ t('ATHENAS.EDIT.KNOWLEDGE.LOADING') }}
            </p>

            <article
              v-else-if="!trainings.length && !editorOpen"
              class="flex flex-col gap-3 p-10 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak items-center text-center"
            >
              <span
                class="size-16 rounded-2xl bg-gradient-to-br from-n-brand/20 to-n-brand/[0.04] ring-1 ring-n-weak grid place-content-center"
              >
                <span class="i-lucide-book-open size-7 text-n-brand" />
              </span>
              <p class="text-[13px] text-n-slate-11 leading-relaxed max-w-md">
                {{ t('ATHENAS.EDIT.KNOWLEDGE.EMPTY') }}
              </p>
            </article>

            <div v-else class="flex flex-col gap-2">
              <article
                v-for="tr in trainings"
                :key="tr.id"
                class="flex items-center gap-3 p-4 rounded-xl bg-n-solid-1 ring-1 ring-n-weak"
              >
                <span
                  class="size-9 rounded-lg bg-n-alpha-2 grid place-content-center flex-shrink-0"
                >
                  <span class="i-lucide-file-text size-4 text-n-slate-11" />
                </span>
                <div class="flex flex-col gap-0.5 min-w-0 flex-1">
                  <span class="text-sm font-medium text-n-slate-12 truncate">
                    {{ tr.title }}
                  </span>
                  <span class="text-[11px] text-n-slate-11">
                    {{ trainingMeta(tr) }}
                  </span>
                </div>
                <Button
                  icon="i-lucide-pencil"
                  size="xs"
                  ghost
                  slate
                  @click="openEditTraining(tr)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  size="xs"
                  ghost
                  ruby
                  @click="removeTraining(tr)"
                />
              </article>
            </div>
          </div>
        </template>

        <!-- TAB: ACTIVITY -->
        <template v-if="currentTab === 'activity'">
          <AthenasAnalytics :assistant-id="id" />
        </template>

        <template v-if="currentTab === 'test'">
          <AthenasPlayground :assistant-id="id" />
        </template>

        <!-- TAB: REVIEW -->
        <template v-if="currentTab === 'review'">
          <AthenasReviewQueue :assistant-id="id" />
        </template>

        <!-- TAB: LAB -->
        <template v-if="currentTab === 'lab'">
          <AthenasPromptLab :assistant-id="id" />
        </template>

        <!-- TAB: RADAR -->
        <template v-if="currentTab === 'radar'">
          <AthenasRadar :assistant-id="id" />
        </template>
      </div>
    </section>

    <Dialog
      ref="confirmDialogRef"
      type="alert"
      :title="confirmState.title"
      :description="confirmState.description"
      @confirm="runConfirmedAction"
    />
  </div>
</template>
