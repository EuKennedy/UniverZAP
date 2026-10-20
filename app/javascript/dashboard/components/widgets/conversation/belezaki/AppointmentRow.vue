<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatMoney, formatStart, statusClass } from './appointmentFormat';

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

// Only the lookup route carries a price; the older agenda route does not,
// and then the line simply ends at the professional.
const price = computed(() =>
  props.appointment.price_cents == null
    ? ''
    : formatMoney(props.appointment.price_cents, locale.value)
);
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
      <span class="flex items-center gap-1 shrink-0">
        <span
          v-if="appointment.needs_deposit"
          class="text-xs px-2 py-0.5 rounded bg-n-amber-5 text-n-amber-12"
          data-testid="deposit-pending"
        >
          {{ $t('CONVERSATION_SIDEBAR.BELEZAKI.DEPOSIT_PENDING') }}
        </span>
        <span
          class="text-xs px-2 py-0.5 rounded"
          :class="statusClass(appointment.status)"
        >
          {{ statusLabel }}
        </span>
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
      <span v-if="price" class="text-n-slate-12">· {{ price }}</span>
    </div>
  </div>
</template>
