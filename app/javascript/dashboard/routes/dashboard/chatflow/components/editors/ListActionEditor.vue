<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { INPUT_CLASS, LABEL_CLASS, HINT_CLASS } from '../../helpers/ui';

// Adicionar/remover de lista de distribuição. Enquanto o recurso de listas não
// estiver na conta, o bloco fica pulado pelo motor — e o painel diz isso.
defineProps({
  config: { type: Object, required: true },
  lists: { type: Array, default: () => [] },
  available: { type: Boolean, default: false },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="list-editor">
    <div
      v-if="!available"
      class="flex gap-2 p-3 rounded-xl bg-n-amber-3 text-n-amber-11 text-xs leading-relaxed"
      data-testid="list-unavailable"
    >
      <Icon icon="i-lucide-info" class="size-4 shrink-0 mt-0.5" />
      {{ t('CHATFLOW.EDITOR.LIST.UNAVAILABLE') }}
    </div>
    <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1 w-fit">
      <button
        v-for="action in ['add', 'remove']"
        :key="action"
        type="button"
        class="px-3 py-1 text-xs font-medium rounded-md transition-colors"
        :class="
          (config.action || 'add') === action
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="emit('update', { action })"
      >
        {{ t(`CHATFLOW.EDITOR.LIST.${action.toUpperCase()}`) }}
      </button>
    </div>
    <label class="flex flex-col gap-1.5">
      <span :class="LABEL_CLASS">{{ t('CHATFLOW.EDITOR.LIST.LIST') }}</span>
      <select
        :value="config.list_id"
        :disabled="!available"
        :class="INPUT_CLASS"
        @change="emit('update', { list_id: Number($event.target.value) })"
      >
        <option :value="undefined">{{ t('CHATFLOW.EDITOR.SELECT') }}</option>
        <option v-for="list in lists" :key="list.id" :value="list.id">
          {{ list.name }}
        </option>
      </select>
    </label>
    <p :class="HINT_CLASS">{{ t('CHATFLOW.EDITOR.LIST.HINT') }}</p>
  </div>
</template>
