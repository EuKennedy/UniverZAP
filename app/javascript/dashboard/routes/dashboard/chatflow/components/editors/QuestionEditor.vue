<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  INPUT_CLASS,
  TEXTAREA_CLASS,
  LABEL_CLASS,
  HINT_CLASS,
  chipClass,
} from '../../helpers/ui';

// Pergunta com captura: o tipo da resposta (que decide a validação), onde
// guardar, a mensagem de erro e quantas tentativas antes de sair por
// "resposta inválida". O texto da pergunta fica no campo comum do painel.
const props = defineProps({
  config: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const attributesByModel = useMapGetter('attributes/getAttributesByModel');

const FIELD_TYPES = [
  { value: 'name', icon: 'i-lucide-user' },
  { value: 'email', icon: 'i-lucide-at-sign' },
  { value: 'phone', icon: 'i-lucide-phone' },
  { value: 'date', icon: 'i-lucide-calendar' },
  { value: 'number', icon: 'i-lucide-hash' },
  { value: 'text', icon: 'i-lucide-text' },
];

// Para onde cada tipo costuma ir: escolher "E-mail" já aponta para o e-mail
// do contato, e o operador só mexe se quiser outro lugar.
const NATURAL_TARGET = { name: 'name', email: 'email', phone: 'phone_number' };

const saveTo = computed(() => props.config.save_to || {});
const scope = computed(() => saveTo.value.scope || 'contact');

const keySuggestions = computed(() => {
  const model =
    scope.value === 'conversation'
      ? 'conversation_attribute'
      : 'contact_attribute';
  const custom = (attributesByModel.value(model) || []).map(
    a => a.attribute_key
  );
  return scope.value === 'contact'
    ? ['name', 'email', 'phone_number', ...custom]
    : custom;
});

const setType = value => {
  const natural = NATURAL_TARGET[value];
  const patch = { field_type: value };
  if (natural && !saveTo.value.key) {
    patch.save_to = { scope: 'contact', key: natural };
  }
  emit('update', patch);
};

const setScope = value =>
  emit('update', { save_to: { scope: value, key: '' } });
const setKey = value =>
  emit('update', { save_to: { scope: scope.value, key: value.trim() } });
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="question-editor">
    <div class="flex flex-col gap-2">
      <span :class="LABEL_CLASS">{{ t('CHATFLOW.EDITOR.QUESTION.TYPE') }}</span>
      <div class="grid grid-cols-3 gap-1.5">
        <button
          v-for="type in FIELD_TYPES"
          :key="type.value"
          type="button"
          class="flex flex-col items-center gap-1 py-2 rounded-lg border text-xs cursor-pointer transition-colors"
          :class="chipClass((config.field_type || 'text') === type.value)"
          :data-testid="`question-type-${type.value}`"
          @click="setType(type.value)"
        >
          <Icon :icon="type.icon" class="size-4" />
          {{ t(`CHATFLOW.EDITOR.QUESTION.TYPES.${type.value.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <span :class="LABEL_CLASS">{{
        t('CHATFLOW.EDITOR.QUESTION.SAVE_TO')
      }}</span>
      <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1 w-fit">
        <button
          v-for="item in ['contact', 'conversation']"
          :key="item"
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md transition-colors"
          :class="
            scope === item
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setScope(item)"
        >
          {{ t(`CHATFLOW.EDITOR.QUESTION.SCOPE.${item.toUpperCase()}`) }}
        </button>
      </div>
      <input
        :value="saveTo.key || ''"
        type="text"
        list="chatflow-question-keys"
        :placeholder="t('CHATFLOW.EDITOR.QUESTION.KEY_PLACEHOLDER')"
        :class="INPUT_CLASS"
        data-testid="question-key"
        @change="setKey($event.target.value)"
      />
      <datalist id="chatflow-question-keys">
        <option v-for="key in keySuggestions" :key="key" :value="key" />
      </datalist>
      <p :class="HINT_CLASS">{{ t('CHATFLOW.EDITOR.QUESTION.KEY_HINT') }}</p>
    </div>

    <label class="flex flex-col gap-1.5">
      <span :class="LABEL_CLASS">{{
        t('CHATFLOW.EDITOR.QUESTION.ERROR')
      }}</span>
      <textarea
        :value="config.error_text"
        rows="2"
        :placeholder="t('CHATFLOW.EDITOR.QUESTION.ERROR_PLACEHOLDER')"
        :class="TEXTAREA_CLASS"
        @input="emit('update', { error_text: $event.target.value })"
      />
    </label>

    <label class="flex items-center gap-2">
      <span :class="LABEL_CLASS">{{
        t('CHATFLOW.EDITOR.QUESTION.ATTEMPTS')
      }}</span>
      <input
        :value="config.max_attempts || 3"
        type="number"
        min="1"
        max="10"
        class="w-20"
        :class="INPUT_CLASS"
        @input="emit('update', { max_attempts: Number($event.target.value) })"
      />
    </label>
    <p :class="HINT_CLASS">{{ t('CHATFLOW.EDITOR.QUESTION.ATTEMPTS_HINT') }}</p>
  </div>
</template>
