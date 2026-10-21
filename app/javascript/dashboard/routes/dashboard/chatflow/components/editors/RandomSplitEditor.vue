<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { INPUT_CLASS, HINT_CLASS } from '../../helpers/ui';
import { splitTotal, nextBranchValue } from '../../helpers/nodeKinds';

const props = defineProps({
  config: { type: Object, required: true },
});

const emit = defineEmits(['update']);

// Teste A/B: cada ramo é uma saída do cartão. O `value` nunca muda depois de
// criado (é o handle da ligação); o operador só edita o nome e o percentual.
const MAX_BRANCHES = 5;

const { t } = useI18n();

const branches = computed(() => props.config.branches || []);
const total = computed(() => splitTotal(branches.value));

const setBranches = next => emit('update', { branches: next });
const patch = (index, change) =>
  setBranches(
    branches.value.map((b, i) => (i === index ? { ...b, ...change } : b))
  );
const add = () => {
  const value = nextBranchValue(branches.value);
  setBranches([
    ...branches.value,
    { value, label: value.toUpperCase(), percent: 0 },
  ]);
};
const remove = index =>
  setBranches(branches.value.filter((_, i) => i !== index));
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="split-editor">
    <div
      v-for="(branch, index) in branches"
      :key="branch.value"
      class="flex items-center gap-2"
    >
      <span
        class="flex items-center justify-center size-7 rounded-md bg-n-violet-3 text-[11px] font-bold text-n-violet-11 shrink-0 uppercase"
      >
        {{ branch.value }}
      </span>
      <input
        :value="branch.label"
        type="text"
        class="flex-1 min-w-0"
        :class="INPUT_CLASS"
        @input="patch(index, { label: $event.target.value })"
      />
      <input
        :value="branch.percent"
        type="number"
        min="0"
        max="100"
        class="w-20"
        :class="INPUT_CLASS"
        :data-testid="`split-percent-${branch.value}`"
        @input="patch(index, { percent: Number($event.target.value) })"
      />
      <span class="text-xs text-n-slate-10">%</span>
      <Button
        v-if="branches.length > 2"
        variant="ghost"
        color="ruby"
        size="sm"
        icon="i-lucide-trash-2"
        @click="remove(index)"
      />
    </div>
    <div class="flex items-center justify-between">
      <Button
        v-if="branches.length < MAX_BRANCHES"
        variant="ghost"
        color="teal"
        size="sm"
        icon="i-lucide-plus"
        :label="t('CHATFLOW.EDITOR.SPLIT.ADD')"
        @click="add"
      />
      <span
        class="text-xs font-medium tabular-nums"
        :class="total === 100 ? 'text-n-teal-11' : 'text-n-amber-11'"
        data-testid="split-total"
      >
        {{ t('CHATFLOW.EDITOR.SPLIT.TOTAL', { total }) }}
      </span>
    </div>
    <p :class="HINT_CLASS">{{ t('CHATFLOW.EDITOR.SPLIT.HINT') }}</p>
  </div>
</template>
