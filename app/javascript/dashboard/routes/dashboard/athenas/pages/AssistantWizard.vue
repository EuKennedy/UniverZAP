<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const STEPS = [
  { key: 'identity', icon: 'i-lucide-user-circle-2' },
  { key: 'personality', icon: 'i-lucide-message-square-heart' },
  { key: 'knowledge', icon: 'i-lucide-book-open', optional: true },
  { key: 'behavior', icon: 'i-lucide-shield-check', optional: true },
  { key: 'review', icon: 'i-lucide-sparkles' },
];

const currentStep = ref(0);
const isSaving = ref(false);
const assistantId = ref(null);
const error = ref('');

const form = reactive({
  name: '',
  role: 'Vendedor SDR',
  description: '',
  avatar_url: '',
  tone: 'sales',
  provider: 'anthropic',
  model: 'claude-sonnet-4-5',
  system_prompt: '',
  temperature: 0.3,
  max_tokens: 1024,
  autopilot_enabled: false,
  encrypted_anthropic_key: '',
  guardrails: {
    stop_words: ['humano', 'atendente', 'falar com gente'],
    max_messages_per_minute: 4,
  },
});

const trainings = ref([]);
const trainingDraft = reactive({ title: '', content: '', category: 'base' });

const stepDef = computed(() => STEPS[currentStep.value]);
const isLastStep = computed(() => currentStep.value === STEPS.length - 1);
const stopWordsCSV = computed({
  get: () => form.guardrails.stop_words.join(', '),
  set: v => {
    form.guardrails.stop_words = v
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
  },
});

const MODELS = [
  {
    key: 'claude-sonnet-4-5',
    title: 'Sonnet 4.5',
    description: 'Equilíbrio entre custo e qualidade. Recomendado.',
    badge: 'Recomendado',
  },
  {
    key: 'claude-opus-4-5',
    title: 'Opus 4.5',
    description: 'Máxima qualidade. Conversas complexas.',
    badge: 'Premium',
  },
  {
    key: 'claude-haiku-4-5',
    title: 'Haiku 4.5',
    description: 'Mais barato e rápido. Alto volume.',
    badge: 'Eco',
  },
];

const TONES = [
  { key: 'sales', label: 'Vendas', icon: 'i-lucide-trending-up' },
  { key: 'support', label: 'Suporte', icon: 'i-lucide-life-buoy' },
  { key: 'friendly', label: 'Amigável', icon: 'i-lucide-smile' },
  { key: 'formal', label: 'Formal', icon: 'i-lucide-briefcase' },
  { key: 'concierge', label: 'Concierge', icon: 'i-lucide-crown' },
];

const ROLE_SUGGESTIONS = [
  'Vendedor SDR',
  'Closer comercial',
  'Atendente de suporte',
  'Recepcionista',
  'Captador de leads',
  'Pós-venda',
];

const PROMPT_TEMPLATES = {
  sales:
    'Você é um(a) SDR responsável por qualificar leads e conduzir conversas até o fechamento. Faça perguntas curtas para entender a dor do cliente. Apresente o produto com benefícios claros. Quando perceber intenção de compra, ofereça agendar reunião com um closer.',
  support:
    'Você é um(a) atendente de suporte. Solucione dúvidas com objetividade e empatia. Se o problema for complexo, peça o pedido/CPF e escale para um humano.',
  friendly:
    'Você é um(a) assistente próximo(a) e acolhedor(a). Use linguagem informal e amigável. Mantenha o tom leve, sem perder a profissionalidade.',
  formal:
    'Você é um(a) assistente corporativo(a). Mantenha tom formal, respeitoso e direto. Trate o cliente por "senhor/senhora" quando apropriado.',
  concierge:
    'Você é um(a) concierge premium. Antecipe necessidades, ofereça soluções personalizadas e mantenha um tom sofisticado em todas as interações.',
};

const validateStep = () => {
  error.value = '';
  if (stepDef.value.key === 'identity') {
    if (!form.name.trim()) {
      error.value = t('ATHENAS.WIZARD.IDENTITY.NAME_REQUIRED');
      return false;
    }
  }
  return true;
};

const finish = async () => {
  isSaving.value = true;
  error.value = '';
  try {
    const { data: assistant } = await AthenasAssistantsAPI.create({
      ai_assistant: { ...form },
    });
    assistantId.value = assistant.id;
    await Promise.all(
      trainings.value.map(tr =>
        AthenasAssistantsAPI.createTraining(assistant.id, {
          title: tr.title,
          source_type: 'text',
          category: tr.category,
          content: tr.content,
        })
      )
    );
    useAlert(t('ATHENAS.WIZARD.SUCCESS'));
    router.replace(
      accountScopedRoute('athenas_assistant_edit', { id: assistant.id })
    );
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isSaving.value = false;
  }
};

const goNext = async () => {
  if (!validateStep()) return;
  if (isLastStep.value) {
    await finish();
    return;
  }
  currentStep.value += 1;
};

const goBack = () => {
  if (currentStep.value > 0) currentStep.value -= 1;
};

const skipStep = () => {
  if (currentStep.value < STEPS.length - 1) currentStep.value += 1;
};

const applyToneTemplate = tone => {
  form.tone = tone;
  if (!form.system_prompt.trim()) {
    form.system_prompt = PROMPT_TEMPLATES[tone] || '';
  }
};

const addTraining = () => {
  if (!trainingDraft.title.trim() || !trainingDraft.content.trim()) return;
  trainings.value.push({ ...trainingDraft });
  trainingDraft.title = '';
  trainingDraft.content = '';
};

const removeTraining = idx => {
  trainings.value.splice(idx, 1);
};
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background">
    <header class="flex items-center gap-3 px-8 py-5 border-b border-n-weak">
      <Button
        icon="i-lucide-arrow-left"
        size="xs"
        ghost
        slate
        :aria-label="t('ATHENAS.WIZARD.BACK')"
        @click="router.back()"
      />
      <div class="flex flex-col gap-0.5">
        <h1 class="text-base font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.WIZARD.HEADER_TITLE') }}
        </h1>
        <p class="text-[12px] text-n-slate-11">
          {{ t(`ATHENAS.WIZARD.STEPS.${stepDef.key.toUpperCase()}.TITLE`) }}
        </p>
      </div>
    </header>

    <nav class="px-8 py-4 border-b border-n-weak">
      <ol class="flex items-center gap-2">
        <li
          v-for="(step, idx) in STEPS"
          :key="step.key"
          class="flex items-center gap-2 flex-1"
        >
          <button
            type="button"
            class="flex items-center gap-2 px-3 py-2 rounded-lg ring-1 transition-all w-full"
            :class="
              idx === currentStep
                ? 'ring-n-brand bg-n-brand/10 text-n-slate-12'
                : idx < currentStep
                  ? 'ring-n-teal-6 bg-n-teal-3 text-n-teal-12'
                  : 'ring-n-weak text-n-slate-11 hover:ring-n-slate-7'
            "
            @click="idx < currentStep && (currentStep = idx)"
          >
            <span
              class="size-5 rounded-full grid place-content-center text-[10px] font-bold ring-1"
              :class="idx <= currentStep ? 'ring-current' : 'ring-n-weak'"
            >
              {{ idx < currentStep ? '✓' : idx + 1 }}
            </span>
            <span class="text-[12px] font-medium truncate">
              {{ t(`ATHENAS.WIZARD.STEPS.${step.key.toUpperCase()}.LABEL`) }}
            </span>
          </button>
        </li>
      </ol>
    </nav>

    <section class="flex-1 overflow-y-auto px-8 py-8">
      <div class="max-w-2xl mx-auto flex flex-col gap-6">
        <header class="flex items-start gap-4">
          <span
            class="size-12 rounded-2xl bg-gradient-to-br from-n-brand/20 to-n-brand/[0.04] ring-1 ring-n-weak grid place-content-center"
          >
            <span :class="stepDef.icon" class="size-6 text-n-brand" />
          </span>
          <div class="flex flex-col gap-1">
            <h2 class="text-xl font-semibold text-n-slate-12 tracking-tight">
              {{
                t(`ATHENAS.WIZARD.STEPS.${stepDef.key.toUpperCase()}.HEADING`)
              }}
            </h2>
            <p class="text-sm text-n-slate-11 leading-relaxed">
              {{
                t(`ATHENAS.WIZARD.STEPS.${stepDef.key.toUpperCase()}.HELPER`)
              }}
            </p>
          </div>
        </header>

        <!-- Step: identity -->
        <div v-if="stepDef.key === 'identity'" class="flex flex-col gap-5">
          <Input
            v-model="form.name"
            :label="t('ATHENAS.WIZARD.IDENTITY.NAME_LABEL')"
            :placeholder="t('ATHENAS.WIZARD.IDENTITY.NAME_PLACEHOLDER')"
            autofocus
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('ATHENAS.WIZARD.IDENTITY.ROLE_LABEL') }}
            </label>
            <Input
              v-model="form.role"
              :placeholder="t('ATHENAS.WIZARD.IDENTITY.ROLE_PLACEHOLDER')"
            />
            <div class="flex flex-wrap gap-1.5 mt-1">
              <button
                v-for="r in ROLE_SUGGESTIONS"
                :key="r"
                type="button"
                class="px-2 py-1 rounded-full text-[11px] ring-1 ring-n-weak text-n-slate-11 hover:ring-n-brand hover:text-n-slate-12 transition-colors"
                @click="form.role = r"
              >
                {{ r }}
              </button>
            </div>
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('ATHENAS.WIZARD.IDENTITY.DESCRIPTION_LABEL') }}
            </label>
            <textarea
              v-model="form.description"
              rows="3"
              :placeholder="
                t('ATHENAS.WIZARD.IDENTITY.DESCRIPTION_PLACEHOLDER')
              "
              class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('ATHENAS.WIZARD.IDENTITY.AVATAR_LABEL') }}
            </label>
            <Input
              v-model="form.avatar_url"
              :placeholder="t('ATHENAS.WIZARD.IDENTITY.AVATAR_PLACEHOLDER')"
            />
          </div>
        </div>

        <!-- Step: personality -->
        <div v-if="stepDef.key === 'personality'" class="flex flex-col gap-5">
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('ATHENAS.WIZARD.PERSONALITY.TONE_LABEL') }}
            </label>
            <div class="grid grid-cols-3 gap-2 sm:grid-cols-5">
              <button
                v-for="t2 in TONES"
                :key="t2.key"
                type="button"
                class="flex flex-col items-center gap-1.5 p-3 rounded-xl ring-1 transition-all"
                :class="
                  form.tone === t2.key
                    ? 'ring-n-brand bg-n-brand/10 text-n-slate-12'
                    : 'ring-n-weak text-n-slate-11 hover:ring-n-slate-7'
                "
                @click="applyToneTemplate(t2.key)"
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
              rows="8"
              :placeholder="t('ATHENAS.WIZARD.PERSONALITY.PROMPT_PLACEHOLDER')"
              class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 font-mono leading-relaxed focus:outline-none focus:border-n-brand resize-y"
            />
            <p class="text-[11px] text-n-slate-11">
              {{ t('ATHENAS.WIZARD.PERSONALITY.PROMPT_HINT') }}
            </p>
          </div>

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
                class="w-full"
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
              {{ t('ATHENAS.WIZARD.PERSONALITY.API_KEY_LABEL') }}
            </label>
            <Input
              v-model="form.encrypted_anthropic_key"
              type="password"
              :placeholder="t('ATHENAS.WIZARD.PERSONALITY.API_KEY_PLACEHOLDER')"
            />
            <p class="text-[11px] text-n-slate-11">
              {{ t('ATHENAS.WIZARD.PERSONALITY.API_KEY_HINT') }}
            </p>
          </div>
        </div>

        <!-- Step: knowledge -->
        <div v-if="stepDef.key === 'knowledge'" class="flex flex-col gap-4">
          <div class="grid grid-cols-1 gap-3">
            <div
              v-for="(tr, idx) in trainings"
              :key="idx"
              class="flex items-start justify-between gap-3 p-3 rounded-xl ring-1 ring-n-weak bg-n-alpha-1"
            >
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span
                    class="px-1.5 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-n-alpha-2 text-n-slate-11"
                  >
                    {{ tr.category }}
                  </span>
                  <h3
                    class="text-[13px] font-semibold text-n-slate-12 truncate"
                  >
                    {{ tr.title }}
                  </h3>
                </div>
                <p class="text-[12px] text-n-slate-11 line-clamp-2">
                  {{ tr.content }}
                </p>
              </div>
              <button
                type="button"
                class="size-7 rounded-md grid place-content-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-11"
                @click="removeTraining(idx)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
          </div>

          <div
            class="flex flex-col gap-3 p-4 rounded-xl ring-1 ring-dashed ring-n-weak"
          >
            <Input
              v-model="trainingDraft.title"
              :label="t('ATHENAS.WIZARD.KNOWLEDGE.TITLE_LABEL')"
              :placeholder="t('ATHENAS.WIZARD.KNOWLEDGE.TITLE_PLACEHOLDER')"
            />
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORY_LABEL') }}
              </label>
              <select
                v-model="trainingDraft.category"
                class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
              >
                <option value="base">
                  {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.BASE') }}
                </option>
                <option value="catalog">
                  {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.CATALOG') }}
                </option>
                <option value="policies">
                  {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.POLICIES') }}
                </option>
                <option value="sales">
                  {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.SALES') }}
                </option>
                <option value="faq">
                  {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.FAQ') }}
                </option>
                <option value="support">
                  {{ t('ATHENAS.WIZARD.KNOWLEDGE.CATEGORIES.SUPPORT') }}
                </option>
              </select>
            </div>
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('ATHENAS.WIZARD.KNOWLEDGE.CONTENT_LABEL') }}
              </label>
              <textarea
                v-model="trainingDraft.content"
                rows="6"
                :placeholder="t('ATHENAS.WIZARD.KNOWLEDGE.CONTENT_PLACEHOLDER')"
                class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
              />
            </div>
            <Button
              icon="i-lucide-plus"
              size="sm"
              ghost
              :label="t('ATHENAS.WIZARD.KNOWLEDGE.ADD')"
              @click="addTraining"
            />
          </div>
        </div>

        <!-- Step: behavior -->
        <div v-if="stepDef.key === 'behavior'" class="flex flex-col gap-5">
          <label
            class="flex items-start gap-3 p-4 rounded-xl ring-1 ring-n-weak cursor-pointer"
            :class="{
              'ring-n-brand bg-n-brand/[0.06]': form.autopilot_enabled,
            }"
          >
            <input
              v-model="form.autopilot_enabled"
              type="checkbox"
              class="mt-0.5"
            />
            <div class="flex flex-col gap-0.5">
              <span class="text-sm font-semibold text-n-slate-12">
                {{ t('ATHENAS.WIZARD.BEHAVIOR.AUTOPILOT_LABEL') }}
              </span>
              <p class="text-[12px] text-n-slate-11 leading-relaxed">
                {{ t('ATHENAS.WIZARD.BEHAVIOR.AUTOPILOT_HINT') }}
              </p>
            </div>
          </label>

          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('ATHENAS.WIZARD.BEHAVIOR.STOP_WORDS_LABEL') }}
            </label>
            <Input
              v-model="stopWordsCSV"
              :placeholder="t('ATHENAS.WIZARD.BEHAVIOR.STOP_WORDS_PLACEHOLDER')"
            />
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
        </div>

        <!-- Step: review -->
        <div v-if="stepDef.key === 'review'" class="flex flex-col gap-4">
          <div
            class="flex flex-col gap-3 p-5 rounded-2xl bg-n-alpha-1 ring-1 ring-n-weak"
          >
            <div class="flex items-center gap-3">
              <span
                class="size-12 rounded-2xl bg-gradient-to-br from-n-brand to-n-teal-9 grid place-content-center"
              >
                <span class="i-lucide-bot size-6 text-white" />
              </span>
              <div class="flex flex-col">
                <h3 class="text-base font-semibold text-n-slate-12">
                  {{ form.name || '—' }}
                </h3>
                <p class="text-[12px] text-n-slate-11">{{ form.role }}</p>
              </div>
            </div>
            <p v-if="form.description" class="text-[13px] text-n-slate-11">
              {{ form.description }}
            </p>
            <div class="grid grid-cols-2 gap-3 text-[12px]">
              <div>
                <span
                  class="text-n-slate-10 uppercase tracking-wider text-[10px]"
                >
                  {{ t('ATHENAS.WIZARD.REVIEW.MODEL') }}
                </span>
                <p class="text-n-slate-12 font-mono">{{ form.model }}</p>
              </div>
              <div>
                <span
                  class="text-n-slate-10 uppercase tracking-wider text-[10px]"
                >
                  {{ t('ATHENAS.WIZARD.REVIEW.TONE') }}
                </span>
                <p class="text-n-slate-12 capitalize">{{ form.tone }}</p>
              </div>
              <div>
                <span
                  class="text-n-slate-10 uppercase tracking-wider text-[10px]"
                >
                  {{ t('ATHENAS.WIZARD.REVIEW.AUTOPILOT') }}
                </span>
                <p class="text-n-slate-12">
                  {{
                    form.autopilot_enabled
                      ? t('ATHENAS.WIZARD.REVIEW.AUTOPILOT_ON')
                      : t('ATHENAS.WIZARD.REVIEW.AUTOPILOT_OFF')
                  }}
                </p>
              </div>
              <div>
                <span
                  class="text-n-slate-10 uppercase tracking-wider text-[10px]"
                >
                  {{ t('ATHENAS.WIZARD.REVIEW.KNOWLEDGE') }}
                </span>
                <p class="text-n-slate-12 tabular-nums">
                  {{
                    t('ATHENAS.WIZARD.REVIEW.KNOWLEDGE_COUNT', {
                      n: trainings.length,
                    })
                  }}
                </p>
              </div>
            </div>
          </div>
          <p class="text-[12px] text-n-slate-11 text-center">
            {{ t('ATHENAS.WIZARD.REVIEW.HELPER') }}
          </p>
        </div>

        <p
          v-if="error"
          class="text-[12px] text-n-ruby-11 bg-n-ruby-3 px-3 py-2 rounded-md ring-1 ring-inset ring-n-ruby-6"
        >
          {{ error }}
        </p>
      </div>
    </section>

    <footer
      class="flex items-center justify-between gap-2 px-8 py-4 border-t border-n-weak"
    >
      <div class="flex items-center gap-2">
        <Button
          v-if="currentStep > 0"
          slate
          faded
          type="button"
          icon="i-lucide-chevron-left"
          :label="t('ATHENAS.WIZARD.PREVIOUS')"
          @click="goBack"
        />
      </div>
      <div class="flex items-center gap-2">
        <Button
          v-if="stepDef.optional && !isLastStep"
          slate
          ghost
          type="button"
          :label="t('ATHENAS.WIZARD.SKIP')"
          @click="skipStep"
        />
        <Button
          type="button"
          :icon="isLastStep ? 'i-lucide-sparkles' : 'i-lucide-chevron-right'"
          :label="
            isLastStep ? t('ATHENAS.WIZARD.FINISH') : t('ATHENAS.WIZARD.NEXT')
          "
          :disabled="isSaving"
          :is-loading="isSaving"
          @click="goNext"
        />
      </div>
    </footer>
  </div>
</template>
