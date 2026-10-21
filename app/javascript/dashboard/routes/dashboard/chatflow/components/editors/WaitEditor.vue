<script setup>
import { useI18n } from 'vue-i18n';
import { INPUT_CLASS, LABEL_CLASS, HINT_CLASS } from '../../helpers/ui';

// Esperar: por quanto tempo (ou até quando) e o que fazer se a cliente
// escrever antes. Quem solta é o mesmo relógio das mensagens agendadas.
defineProps({
  config: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const { t } = useI18n();

const UNITS = ['minutes', 'hours', 'days'];
const ON_REPLY = ['stop', 'keep', 'branch'];
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="wait-editor">
    <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1 w-fit">
      <button
        v-for="mode in ['duration', 'until']"
        :key="mode"
        type="button"
        class="px-3 py-1 text-xs font-medium rounded-md transition-colors"
        :class="
          (config.mode || 'duration') === mode
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        :data-testid="`wait-mode-${mode}`"
        @click="emit('update', { mode })"
      >
        {{ t(`CHATFLOW.EDITOR.WAIT.MODE_${mode.toUpperCase()}`) }}
      </button>
    </div>

    <div v-if="config.mode !== 'until'" class="flex items-center gap-2">
      <input
        :value="config.amount || 1"
        type="number"
        min="1"
        class="w-24"
        :class="INPUT_CLASS"
        data-testid="wait-amount"
        @input="emit('update', { amount: Number($event.target.value) })"
      />
      <select
        :value="config.unit || 'minutes'"
        class="flex-1"
        :class="INPUT_CLASS"
        @change="emit('update', { unit: $event.target.value })"
      >
        <option v-for="unit in UNITS" :key="unit" :value="unit">
          {{ t(`CHATFLOW.EDITOR.UNIT.${unit.toUpperCase()}`) }}
        </option>
      </select>
    </div>
    <input
      v-else
      :value="config.until"
      type="datetime-local"
      :class="INPUT_CLASS"
      data-testid="wait-until"
      @change="emit('update', { until: $event.target.value })"
    />

    <div class="flex flex-col gap-2">
      <span :class="LABEL_CLASS">{{ t('CHATFLOW.EDITOR.WAIT.ON_REPLY') }}</span>
      <label
        v-for="option in ON_REPLY"
        :key="option"
        class="flex items-start gap-2 p-2.5 rounded-lg border cursor-pointer"
        :class="
          (config.on_reply || 'stop') === option
            ? 'border-n-teal-7 bg-n-teal-3/40'
            : 'border-n-weak'
        "
      >
        <input
          type="radio"
          class="mt-0.5 accent-n-teal-9"
          :checked="(config.on_reply || 'stop') === option"
          :data-testid="`wait-on-reply-${option}`"
          @change="emit('update', { on_reply: option })"
        />
        <span class="flex flex-col">
          <span class="text-sm text-n-slate-12">
            {{ t(`CHATFLOW.EDITOR.WAIT.REPLY_${option.toUpperCase()}`) }}
          </span>
          <span class="text-[11px] text-n-slate-10">
            {{ t(`CHATFLOW.EDITOR.WAIT.REPLY_${option.toUpperCase()}_HINT`) }}
          </span>
        </span>
      </label>
    </div>

    <label class="flex items-start gap-2 cursor-pointer">
      <input
        type="checkbox"
        class="mt-0.5 accent-n-teal-9"
        :checked="Boolean(config.respect_window)"
        @change="emit('update', { respect_window: $event.target.checked })"
      />
      <span class="flex flex-col">
        <span class="text-sm text-n-slate-12">
          {{ t('CHATFLOW.EDITOR.WAIT.WINDOW') }}
        </span>
        <span :class="HINT_CLASS">{{
          t('CHATFLOW.EDITOR.WAIT.WINDOW_HINT')
        }}</span>
      </span>
    </label>
  </div>
</template>
