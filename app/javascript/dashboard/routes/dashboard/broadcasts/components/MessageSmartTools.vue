<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import BroadcastsAPI from 'dashboard/api/broadcasts';
import Button from 'dashboard/components-next/button/Button.vue';
import { VARIABLES } from 'dashboard/helper/scheduledMessages';

const props = defineProps({
  text: { type: String, default: '' },
  variants: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:text', 'update:variants']);

// Ferramentas do texto de UM bloco do disparo: variáveis, versões (escritas
// à mão ou sugeridas pela IA) e modelos. Modelos são as respostas prontas da
// conta (as mesmas do "/" no composer) — nada de um segundo cadastro de textos.
const MAX_VARIANTS = 2;

const { t } = useI18n();
const store = useStore();
const cannedResponses = useMapGetter('getCannedResponses');

const isSuggesting = ref(false);
const selectedTemplate = ref('');

const canAddVariant = computed(() => props.variants.length < MAX_VARIANTS);
const hasSpintax = computed(() => /\{[^{}]*\|[^{}]*\}/.test(props.text));

const tokenOf = name => `{${name}}`;
const spintaxExample = '{Oi|Olá|Oie}';

const insertVariable = name => {
  const separator = props.text && !props.text.endsWith(' ') ? ' ' : '';
  emit('update:text', `${props.text}${separator}${tokenOf(name)}`);
};

const setVariant = (index, value) => {
  const next = [...props.variants];
  next[index] = value;
  emit('update:variants', next);
};

const addVariant = () => emit('update:variants', [...props.variants, '']);

const removeVariant = index =>
  emit(
    'update:variants',
    props.variants.filter((_, i) => i !== index)
  );

const suggest = async () => {
  if (!props.text.trim()) {
    useAlert(t('BROADCAST.SMART.VARIATIONS_NEED_TEXT'));
    return;
  }
  isSuggesting.value = true;
  try {
    const { data } = await BroadcastsAPI.variations(props.text);
    emit('update:variants', (data.variations || []).slice(0, MAX_VARIANTS));
    useAlert(t('BROADCAST.SMART.VARIATIONS_READY'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('BROADCAST.SMART.VARIATIONS_ERROR')
    );
  } finally {
    isSuggesting.value = false;
  }
};

const useTemplate = () => {
  const template = cannedResponses.value.find(
    item => String(item.id) === String(selectedTemplate.value)
  );
  if (template) emit('update:text', template.content);
  selectedTemplate.value = '';
};

const saveAsTemplate = async () => {
  if (!props.text.trim()) return;
  // eslint-disable-next-line no-alert
  const name = window.prompt(t('BROADCAST.SMART.TEMPLATE_NAME_PROMPT'));
  if (!name) return;
  try {
    await store.dispatch('createCannedResponse', {
      short_code: name.trim().toLowerCase().replace(/\s+/g, '-'),
      content: props.text,
    });
    useAlert(t('BROADCAST.SMART.TEMPLATE_SAVED'));
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.SMART.TEMPLATE_ERROR'));
  }
};

onMounted(() => store.dispatch('getCannedResponse'));

const textareaClass =
  'px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 resize-y';
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="message-smart-tools">
    <div class="flex flex-wrap items-center gap-1">
      <span class="text-[11px] text-n-slate-10">
        {{ t('SCHEDULED_MESSAGES.VARIABLES.LABEL') }}
      </span>
      <button
        v-for="name in VARIABLES"
        :key="name"
        type="button"
        class="px-2 py-0.5 rounded-md bg-n-alpha-2 text-[11px] text-n-slate-11 hover:bg-n-alpha-3 hover:text-n-slate-12"
        :data-testid="`variable-${name}`"
        @click="insertVariable(name)"
      >
        {{ t(`SCHEDULED_MESSAGES.VARIABLES.${name.toUpperCase()}`) }}
      </button>
    </div>
    <p class="m-0 text-[11px] text-n-slate-10">
      {{ t('BROADCAST.SMART.SPINTAX_HINT') }}
      <code class="px-1 rounded bg-n-alpha-2 text-n-slate-12">
        {{ spintaxExample }}
      </code>
      <span
        v-if="hasSpintax"
        class="text-n-teal-11 before:content-['·'] before:mx-1"
      >
        {{ t('BROADCAST.SMART.SPINTAX_ON') }}
      </span>
    </p>

    <div class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('BROADCAST.SMART.VARIANTS_TITLE') }}
        </span>
        <Button
          variant="faded"
          color="teal"
          size="xs"
          icon="i-lucide-sparkles"
          :label="t('BROADCAST.SMART.SUGGEST_VARIATIONS')"
          :is-loading="isSuggesting"
          data-testid="suggest-variations"
          @click="suggest"
        />
      </div>
      <p class="m-0 text-[11px] text-n-slate-10">
        {{ t('BROADCAST.SMART.VARIANTS_HINT') }}
      </p>
      <div
        v-for="(variant, index) in variants"
        :key="`variant-${index}`"
        class="flex items-start gap-2"
      >
        <span
          class="inline-flex items-center justify-center size-6 mt-1 rounded-md bg-n-alpha-2 text-[11px] text-n-slate-11 shrink-0"
        >
          {{ String.fromCharCode(66 + index) }}
        </span>
        <textarea
          :value="variant"
          rows="2"
          class="flex-1"
          :class="textareaClass"
          :data-testid="`variant-${index}`"
          @input="setVariant(index, $event.target.value)"
        />
        <Button
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-x"
          @click="removeVariant(index)"
        />
      </div>
      <Button
        v-if="canAddVariant"
        class="self-start"
        variant="ghost"
        color="slate"
        size="xs"
        icon="i-lucide-plus"
        :label="t('BROADCAST.SMART.ADD_VARIANT')"
        @click="addVariant"
      />
    </div>

    <div class="flex flex-wrap items-center gap-2">
      <select
        v-model="selectedTemplate"
        class="h-8 px-2 rounded-lg bg-n-alpha-1 border border-n-weak text-xs text-n-slate-12 !mb-0 max-w-xs"
        data-testid="template-picker"
        @change="useTemplate"
      >
        <option value="">{{ t('BROADCAST.SMART.USE_TEMPLATE') }}</option>
        <option
          v-for="template in cannedResponses"
          :key="template.id"
          :value="template.id"
        >
          {{ template.short_code }}
        </option>
      </select>
      <Button
        variant="ghost"
        color="slate"
        size="xs"
        icon="i-lucide-bookmark-plus"
        :label="t('BROADCAST.SMART.SAVE_TEMPLATE')"
        :disabled="!text.trim()"
        @click="saveAsTemplate"
      />
    </div>
  </div>
</template>
