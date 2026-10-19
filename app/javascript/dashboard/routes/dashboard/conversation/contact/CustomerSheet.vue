<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CustomerSheetRow from './CustomerSheetRow.vue';
import ScheduleDialog from './ScheduleDialog.vue';
import {
  customerTypeOf,
  formatAppointment,
  formatPhone,
  isLidContact,
  originOf,
  stageOf,
} from './helpers/customerSheet';

// Who this customer is and what comes next, from data the account already
// has. Pure view: the store wiring lives in CustomerSheetSection.
const props = defineProps({
  contact: { type: Object, default: () => ({}) },
  conversation: { type: Object, default: () => ({}) },
  // Stages of the account's vertical, in order ({ title, color, closes_conversation }).
  stages: { type: Array, default: () => [] },
  // Conversation attribute definitions (for the service list).
  attributeDefinitions: { type: Array, default: () => [] },
  previousConversations: { type: Array, default: () => [] },
  isScheduling: { type: Boolean, default: false },
});

const emit = defineEmits(['update', 'schedule']);

const { t, locale } = useI18n();

const scheduleDialog = ref(null);

const attributes = computed(() => props.conversation.custom_attributes || {});
const labels = computed(() => props.conversation.labels || []);

const phone = computed(() => formatPhone(props.contact.phone_number));
const hasNoNumber = computed(() => isLidContact(props.contact));

const stage = computed(() => stageOf(labels.value, props.stages));
const origin = computed(() => originOf(props.conversation, props.contact));
const closingTitles = computed(() =>
  props.stages.filter(s => s.closes_conversation).map(s => s.title)
);
const customerType = computed(() =>
  customerTypeOf({
    contact: props.contact,
    conversation: props.conversation,
    previousConversations: props.previousConversations,
    closingTitles: closingTitles.value,
  })
);

const serviceOptions = computed(
  () =>
    props.attributeDefinitions.find(d => d.attribute_key === 'servico')
      ?.attribute_values || []
);

const appointment = computed(() =>
  formatAppointment(attributes.value.data_agendamento, locale.value)
);
const repurchase = computed(() => {
  const weeks = Number(attributes.value.ciclo_recompra_semanas);
  return weeks > 0 ? t('CONTACT_PANEL.SHEET.REPURCHASE_EVERY', weeks) : '';
});

// Belezaki (next phase) adds "última visita" and "gasto acumulado" here as
// two more rows once the integration delivers them.
const rows = computed(() => [
  {
    name: 'servico',
    label: t('CONTACT_PANEL.SHEET.SERVICE'),
    value: attributes.value.servico || '',
    rawValue: attributes.value.servico || '',
    type: 'list',
    options: serviceOptions.value,
  },
  {
    name: 'profissional',
    label: t('CONTACT_PANEL.SHEET.PROFESSIONAL'),
    value: attributes.value.profissional || '',
    rawValue: attributes.value.profissional || '',
    type: 'text',
  },
  {
    name: 'data_agendamento',
    label: t('CONTACT_PANEL.SHEET.APPOINTMENT'),
    value: appointment.value,
    rawValue: attributes.value.data_agendamento || '',
    type: 'datetime',
  },
  {
    name: 'ciclo_recompra_semanas',
    label: t('CONTACT_PANEL.SHEET.REPURCHASE'),
    value: repurchase.value,
    rawValue: attributes.value.ciclo_recompra_semanas ?? '',
    type: 'number',
  },
]);

const copyPhone = async () => {
  await copyTextToClipboard(props.contact.phone_number);
  useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
};

const openSchedule = () => scheduleDialog.value?.open();
const closeSchedule = () => scheduleDialog.value?.close();

defineExpose({ closeSchedule });
</script>

<template>
  <div class="flex flex-col w-full gap-2" data-testid="customer-sheet">
    <div class="flex items-center gap-2 min-h-6" data-testid="sheet-phone">
      <span class="i-ri-whatsapp-line size-4 shrink-0 text-n-teal-11" />
      <span v-if="hasNoNumber" class="text-sm text-n-slate-10">
        {{ t('CONTACT_PANEL.SHEET.NO_PHONE') }}
      </span>
      <template v-else-if="phone">
        <span class="text-sm text-n-slate-12 truncate" :title="phone">
          {{ phone }}
        </span>
        <button
          type="button"
          class="shrink-0 size-5 inline-flex items-center justify-center rounded-md text-n-slate-10 hover:text-n-slate-12"
          :title="t('CONTACT_PANEL.SHEET.COPY_PHONE')"
          @click="copyPhone"
        >
          <span class="i-lucide-clipboard size-3" />
        </button>
      </template>
      <span v-else class="text-sm text-n-slate-10">
        {{ t('CONTACT_PANEL.SHEET.EMPTY') }}
      </span>
    </div>

    <div class="flex flex-col gap-1.5">
      <CustomerSheetRow name="stage" :label="t('CONTACT_PANEL.SHEET.STAGE')">
        <span
          v-if="stage"
          class="inline-flex items-center gap-1.5 text-sm text-n-slate-12 truncate"
          :title="stage.description || stage.title"
        >
          <span
            class="size-2 rounded-full shrink-0"
            :style="{ backgroundColor: stage.color }"
          />
          {{ stage.title }}
        </span>
        <span v-else class="text-sm text-n-slate-10">
          {{ t('CONTACT_PANEL.SHEET.EMPTY') }}
        </span>
      </CustomerSheetRow>

      <CustomerSheetRow name="origin" :label="t('CONTACT_PANEL.SHEET.ORIGIN')">
        <span class="text-sm text-n-slate-12 truncate">
          {{
            origin.source === 'ad'
              ? t('CONTACT_PANEL.SHEET.ORIGIN_AD')
              : t('CONTACT_PANEL.SHEET.ORIGIN_ORGANIC')
          }}<template v-if="origin.title">
            <a
              v-if="origin.url"
              :href="origin.url"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-blue-11 hover:underline before:content-['·'] before:mx-1 before:text-n-slate-10"
            >
              {{ origin.title }}
            </a>
            <span
              v-else
              class="before:content-['·'] before:mx-1 before:text-n-slate-10"
            >
              {{ origin.title }}
            </span>
          </template>
        </span>
      </CustomerSheetRow>

      <CustomerSheetRow name="type" :label="t('CONTACT_PANEL.SHEET.TYPE')">
        <span class="text-sm text-n-slate-12">
          {{
            customerType === 'recurring'
              ? t('CONTACT_PANEL.SHEET.TYPE_RECURRING')
              : t('CONTACT_PANEL.SHEET.TYPE_NEW')
          }}
        </span>
      </CustomerSheetRow>
    </div>

    <div class="flex flex-col gap-1.5 pt-2 border-t border-n-weak">
      <CustomerSheetRow
        v-for="row in rows"
        :key="row.name"
        :name="row.name"
        :label="row.label"
        :value="row.value"
        :raw-value="row.rawValue"
        :type="row.type"
        :options="row.options"
        editable
        @update="value => emit('update', row.name, value)"
      />
    </div>

    <div class="flex items-center gap-2 pt-1">
      <NextButton
        :label="t('CONTACT_PANEL.SHEET.SCHEDULE.BUTTON')"
        icon="i-lucide-calendar-plus"
        sm
        :is-loading="isScheduling"
        data-testid="sheet-schedule"
        @click="openSchedule"
      />
    </div>

    <ScheduleDialog
      ref="scheduleDialog"
      :initial-values="attributes"
      :service-options="serviceOptions"
      :is-loading="isScheduling"
      @confirm="payload => emit('schedule', payload)"
    />
  </div>
</template>
