<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { INPUT_CLASS, LABEL_CLASS, HINT_CLASS } from '../../helpers/ui';

const props = defineProps({
  config: { type: Object, required: true },
  flows: { type: Array, default: () => [] },
  currentFlowId: { type: [Number, String], default: null },
});
const emit = defineEmits(['update']);

const { t } = useI18n();

const choices = computed(() =>
  props.flows.filter(f => Number(f.id) !== Number(props.currentFlowId))
);
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="goto-editor">
    <span :class="LABEL_CLASS">{{ t('CHATFLOW.EDITOR.GOTO.FLOW') }}</span>
    <select
      :value="config.chatflow_id"
      :class="INPUT_CLASS"
      @change="emit('update', { chatflow_id: Number($event.target.value) })"
    >
      <option :value="undefined">{{ t('CHATFLOW.EDITOR.SELECT') }}</option>
      <option v-for="flow in choices" :key="flow.id" :value="flow.id">
        {{ flow.name }} ·
        {{ t(`CHATFLOW.STATUS.${flow.status.toUpperCase()}`) }}
      </option>
    </select>
    <p :class="HINT_CLASS">{{ t('CHATFLOW.EDITOR.GOTO.HINT') }}</p>
  </div>
</template>
