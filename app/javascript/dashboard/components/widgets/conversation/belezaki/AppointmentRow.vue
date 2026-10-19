<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatStart, statusClass } from './appointmentFormat';

const props = defineProps({
  appointment: {
    type: Object,
    required: true,
  },
  timezone: {
    type: String,
    default: '',
  },
  emphasis: {
    type: Boolean,
    default: false,
  },
});

const { t, locale, te } = useI18n();

const when = computed(() =>
  formatStart(props.appointment.start, props.timezone, locale.value)
);

const statusLabel = computed(() => {
  const key = `CONVERSATION_SIDEBAR.BELEZAKI.STATUS.${props.appointment.status}`;
  return te(key) ? t(key) : props.appointment.status;
});
</script>

<template>
  <div class="flex flex-col gap-0.5 py-2">
    <div class="flex items-start justify-between gap-2">
      <span
        class="text-n-slate-12"
        :class="emphasis ? 'text-base font-semibold' : 'text-sm font-medium'"
      >
        {{ when }}
      </span>
      <span
        class="text-xs px-2 py-0.5 rounded shrink-0"
        :class="statusClass(appointment.status)"
      >
        {{ statusLabel }}
      </span>
    </div>
    <div class="text-sm text-n-slate-11 truncate">
      {{ appointment.service }}
      <span v-if="appointment.professional">
        ·
        {{
          $t('CONVERSATION_SIDEBAR.BELEZAKI.WITH', {
            professional: appointment.professional,
          })
        }}
      </span>
    </div>
  </div>
</template>
