<script setup>
import { useI18n } from 'vue-i18n';
import { LABEL_CLASS, HINT_CLASS } from '../../helpers/ui';

defineProps({
  config: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="typing-editor">
    <span :class="LABEL_CLASS">
      {{
        t('CHATFLOW.EDITOR.TYPING.SECONDS', { seconds: config.seconds || 3 })
      }}
    </span>
    <input
      :value="config.seconds || 3"
      type="range"
      min="1"
      max="20"
      class="accent-n-teal-9"
      @input="emit('update', { seconds: Number($event.target.value) })"
    />
    <p :class="HINT_CLASS">{{ t('CHATFLOW.EDITOR.TYPING.HINT') }}</p>
  </div>
</template>
