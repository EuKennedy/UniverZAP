<script setup>
import { computed, nextTick, ref } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { fromDateTimeLocal, toDateTimeLocal } from './helpers/customerSheet';

const props = defineProps({
  name: { type: String, required: true },
  label: { type: String, required: true },
  // What the row shows; empty shows a dash.
  value: { type: String, default: '' },
  // What the editor starts from (the stored value).
  rawValue: { type: [String, Number], default: '' },
  editable: { type: Boolean, default: false },
  type: {
    type: String,
    default: 'text',
    validator: value => ['text', 'number', 'list', 'datetime'].includes(value),
  },
  options: { type: Array, default: () => [] },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const isEditing = ref(false);
const draft = ref('');
const inputRef = ref(null);

const inputType = computed(() => {
  if (props.type === 'datetime') return 'datetime-local';
  return props.type === 'number' ? 'number' : 'text';
});

const startEditing = () => {
  if (!props.editable) return;
  draft.value =
    props.type === 'datetime'
      ? toDateTimeLocal(props.rawValue)
      : String(props.rawValue ?? '');
  isEditing.value = true;
  nextTick(() => inputRef.value?.focus());
};

const cancel = () => {
  isEditing.value = false;
};

const save = () => {
  if (!isEditing.value) return;
  isEditing.value = false;
  let next = draft.value;
  if (props.type === 'datetime') next = fromDateTimeLocal(draft.value);
  if (props.type === 'number' && draft.value !== '') next = Number(draft.value);
  if (next !== props.rawValue) emit('update', next);
};

const fieldClass =
  'w-full h-7 px-2 text-sm rounded-md outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand bg-n-alpha-black2 text-n-slate-12 !mb-0';
</script>

<template>
  <div
    class="group/row flex items-start gap-2 w-full min-h-6"
    :data-testid="`sheet-row-${name}`"
  >
    <span class="w-24 shrink-0 pt-0.5 text-xs text-n-slate-11 truncate">
      {{ label }}
    </span>

    <div
      v-if="isEditing"
      v-on-click-outside="cancel"
      class="flex items-center flex-1 min-w-0 gap-1"
    >
      <select
        v-if="type === 'list'"
        ref="inputRef"
        v-model="draft"
        :class="fieldClass"
        @change="save"
        @keydown.esc="cancel"
      >
        <option value="">{{ t('CONTACT_PANEL.SHEET.EMPTY') }}</option>
        <option v-for="option in options" :key="option" :value="option">
          {{ option }}
        </option>
      </select>
      <input
        v-else
        ref="inputRef"
        v-model="draft"
        :type="inputType"
        :class="fieldClass"
        @keydown.enter.prevent="save"
        @keydown.esc="cancel"
      />
      <button
        type="button"
        class="shrink-0 size-6 inline-flex items-center justify-center rounded-md text-n-teal-11 hover:bg-n-alpha-2"
        :title="t('CONTACT_PANEL.SHEET.SAVE')"
        @click="save"
      >
        <span class="i-lucide-check size-3.5" />
      </button>
    </div>

    <div v-else class="flex items-center flex-1 min-w-0 gap-1">
      <slot>
        <span
          class="text-sm truncate"
          :class="value ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ value || t('CONTACT_PANEL.SHEET.EMPTY') }}
        </span>
      </slot>
      <button
        v-if="editable"
        type="button"
        class="shrink-0 size-5 inline-flex items-center justify-center rounded-md text-n-slate-10 opacity-0 group-hover/row:opacity-100 focus:opacity-100 hover:text-n-slate-12 transition-opacity"
        :title="t('CONTACT_PANEL.CLICK_TO_EDIT')"
        :data-testid="`sheet-edit-${name}`"
        @click="startEditing"
      >
        <span class="i-lucide-pencil size-3" />
      </button>
    </div>
  </div>
</template>
