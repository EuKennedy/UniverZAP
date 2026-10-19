<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { fromDateTimeLocal, toDateTimeLocal } from './helpers/customerSheet';

const props = defineProps({
  // Values already on the conversation, used to prefill the form.
  initialValues: { type: Object, default: () => ({}) },
  serviceOptions: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm']);

const { t } = useI18n();

const dialogRef = ref(null);
const form = ref({
  servico: '',
  profissional: '',
  data_agendamento: '',
  ciclo_recompra_semanas: '',
});

const canConfirm = computed(() => Boolean(form.value.data_agendamento));

const open = () => {
  const initial = props.initialValues;
  form.value = {
    servico: initial.servico || '',
    profissional: initial.profissional || '',
    data_agendamento: toDateTimeLocal(initial.data_agendamento),
    ciclo_recompra_semanas: initial.ciclo_recompra_semanas ?? '',
  };
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const confirm = () => {
  if (!canConfirm.value) return;
  emit('confirm', {
    servico: form.value.servico,
    profissional: form.value.profissional,
    data_agendamento: fromDateTimeLocal(form.value.data_agendamento),
    ciclo_recompra_semanas: form.value.ciclo_recompra_semanas,
  });
};

defineExpose({ open, close });

const fieldClass =
  'w-full h-9 px-3 text-sm rounded-lg outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand bg-n-alpha-black2 text-n-slate-12 !mb-0';
const labelClass = 'text-xs font-medium text-n-slate-11';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACT_PANEL.SHEET.SCHEDULE.TITLE')"
    :description="t('CONTACT_PANEL.SHEET.SCHEDULE.DESCRIPTION')"
    :confirm-button-label="t('CONTACT_PANEL.SHEET.SCHEDULE.CONFIRM')"
    :disable-confirm-button="!canConfirm"
    :is-loading="isLoading"
    width="sm"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-3" data-testid="schedule-form">
      <label class="flex flex-col gap-1">
        <span :class="labelClass">{{ t('CONTACT_PANEL.SHEET.SERVICE') }}</span>
        <select
          v-if="serviceOptions.length"
          v-model="form.servico"
          :class="fieldClass"
          data-testid="schedule-service"
        >
          <option value="">
            {{ t('CONTACT_PANEL.SHEET.SCHEDULE.SERVICE_PLACEHOLDER') }}
          </option>
          <option
            v-for="option in serviceOptions"
            :key="option"
            :value="option"
          >
            {{ option }}
          </option>
        </select>
        <input
          v-else
          v-model="form.servico"
          type="text"
          :class="fieldClass"
          data-testid="schedule-service"
        />
      </label>
      <label class="flex flex-col gap-1">
        <span :class="labelClass">
          {{ t('CONTACT_PANEL.SHEET.PROFESSIONAL') }}
        </span>
        <input
          v-model="form.profissional"
          type="text"
          :class="fieldClass"
          data-testid="schedule-professional"
        />
      </label>
      <label class="flex flex-col gap-1">
        <span :class="labelClass">
          {{ t('CONTACT_PANEL.SHEET.SCHEDULE.DATE') }}
        </span>
        <input
          v-model="form.data_agendamento"
          type="datetime-local"
          :class="fieldClass"
          required
          data-testid="schedule-date"
        />
      </label>
      <label class="flex flex-col gap-1">
        <span :class="labelClass">
          {{ t('CONTACT_PANEL.SHEET.SCHEDULE.REPURCHASE_WEEKS') }}
        </span>
        <input
          v-model="form.ciclo_recompra_semanas"
          type="number"
          min="1"
          :class="fieldClass"
          data-testid="schedule-repurchase"
        />
      </label>
    </div>
  </Dialog>
</template>
