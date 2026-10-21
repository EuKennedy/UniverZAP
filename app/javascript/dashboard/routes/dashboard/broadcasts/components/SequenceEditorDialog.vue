<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { VARIABLES } from 'dashboard/helper/scheduledMessages';
import { offsetToStep, stepToOffset } from '../helpers/sequences';

const emit = defineEmits(['save']);

// Cria/edita uma sequência: cada passo é "N horas/dias antes/depois do
// horário agendado" + texto. Ligar fica fora daqui, no cartão da lista, com
// confirmação — editar nunca liga nada sozinho.
const MAX_STEPS = 5;

const { t } = useI18n();

const dialogRef = ref(null);
const editing = ref(null);
const name = ref('');
const steps = ref([]);
const isSaving = ref(false);

const emptyStep = () => ({
  amount: 1,
  unit: 'days',
  direction: 'before',
  text: '',
  cancelIfReply: true,
});

const canSave = computed(
  () =>
    Boolean(name.value.trim()) &&
    steps.value.length > 0 &&
    steps.value.every(step => step.text.trim() && Number(step.amount) > 0)
);

const open = (sequence = null) => {
  editing.value = sequence;
  name.value = sequence?.name || '';
  steps.value = sequence?.steps?.length
    ? sequence.steps.map(offsetToStep)
    : [emptyStep()];
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();
const setSaving = value => {
  isSaving.value = value;
};

const addStep = () => steps.value.push(emptyStep());
const removeStep = index => steps.value.splice(index, 1);

const insertVariable = (step, variable) => {
  // eslint-disable-next-line no-param-reassign
  step.text = `${step.text}${step.text && !step.text.endsWith(' ') ? ' ' : ''}{${variable}}`;
};

const save = () => {
  if (!canSave.value) return;
  emit('save', {
    id: editing.value?.id,
    name: name.value.trim(),
    steps: steps.value.map(stepToOffset),
  });
};

defineExpose({ open, close, setSaving });

const fieldClass =
  'h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 !mb-0';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      editing
        ? t('BROADCAST.SEQUENCES.EDIT_TITLE')
        : t('BROADCAST.SEQUENCES.NEW_TITLE')
    "
    :description="t('BROADCAST.SEQUENCES.DIALOG_DESCRIPTION')"
    :confirm-button-label="t('BROADCAST.SEQUENCES.SAVE')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="save"
  >
    <div class="flex flex-col gap-4" data-testid="sequence-editor">
      <input
        v-model="name"
        type="text"
        :placeholder="t('BROADCAST.SEQUENCES.NAME_PLACEHOLDER')"
        :class="fieldClass"
        data-testid="sequence-name"
      />
      <div
        v-for="(step, index) in steps"
        :key="`step-${index}`"
        class="flex flex-col gap-2 p-3 rounded-xl border border-n-weak"
        data-testid="sequence-step"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span
            class="inline-flex items-center justify-center size-6 rounded-md bg-n-teal-3 text-[11px] font-semibold text-n-teal-11"
          >
            {{ index + 1 }}
          </span>
          <input
            v-model.number="step.amount"
            type="number"
            min="1"
            class="w-20"
            :class="fieldClass"
          />
          <select v-model="step.unit" :class="fieldClass">
            <option value="hours">{{ t('BROADCAST.SEQUENCES.HOURS') }}</option>
            <option value="days">{{ t('BROADCAST.SEQUENCES.DAYS') }}</option>
          </select>
          <select v-model="step.direction" :class="fieldClass">
            <option value="before">
              {{ t('BROADCAST.SEQUENCES.BEFORE') }}
            </option>
            <option value="after">{{ t('BROADCAST.SEQUENCES.AFTER') }}</option>
          </select>
          <span class="text-xs text-n-slate-11">
            {{ t('BROADCAST.SEQUENCES.OF_APPOINTMENT') }}
          </span>
          <Button
            v-if="steps.length > 1"
            class="ms-auto"
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-trash-2"
            @click="removeStep(index)"
          />
        </div>
        <textarea
          v-model="step.text"
          rows="3"
          :placeholder="t('BROADCAST.SEQUENCES.TEXT_PLACEHOLDER')"
          class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 resize-y"
        />
        <div class="flex flex-wrap items-center gap-1">
          <button
            v-for="variable in VARIABLES"
            :key="variable"
            type="button"
            class="px-2 py-0.5 rounded-md bg-n-alpha-2 text-[11px] text-n-slate-11 hover:bg-n-alpha-3"
            @click="insertVariable(step, variable)"
          >
            {{ t(`SCHEDULED_MESSAGES.VARIABLES.${variable.toUpperCase()}`) }}
          </button>
        </div>
        <label class="flex items-center gap-2 text-xs text-n-slate-11">
          <input v-model="step.cancelIfReply" type="checkbox" />
          {{ t('SCHEDULED_MESSAGES.DIALOG.CANCEL_IF_REPLY') }}
        </label>
      </div>
      <Button
        v-if="steps.length < MAX_STEPS"
        class="self-start"
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-plus"
        :label="t('BROADCAST.SEQUENCES.ADD_STEP')"
        @click="addStep"
      />
    </div>
  </Dialog>
</template>
