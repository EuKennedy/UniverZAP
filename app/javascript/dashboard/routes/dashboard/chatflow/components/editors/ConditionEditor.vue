<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  INPUT_CLASS,
  LABEL_CLASS,
  HINT_CLASS,
  chipClass,
} from '../../helpers/ui';

// Se/senão: uma lista de regras ligadas por "todas" ou "qualquer uma". Cada
// tipo de regra tem seus próprios campos; o motor ignora tipos desconhecidos.
const props = defineProps({
  config: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');

const RULE_TYPES = [
  'label',
  'attribute',
  'lead_source',
  'recurring',
  'business_hours',
  'schedule',
];
const OPERATORS = [
  'equals',
  'not_equals',
  'contains',
  'present',
  'blank',
  'greater',
  'less',
];
const WEEKDAYS = [1, 2, 3, 4, 5, 6, 0];

const RULE_DEFAULTS = {
  label: { operator: 'has', label_ids: [] },
  attribute: { scope: 'contact', key: '', operator: 'equals', value: '' },
  lead_source: { value: 'anuncio_facebook' },
  recurring: { value: true },
  business_hours: { value: 'open' },
  schedule: { weekdays: [1, 2, 3, 4, 5], from: '09:00', to: '18:00' },
};

const rules = computed(() => props.config.rules || []);

const setRules = next => emit('update', { rules: next });
const addRule = type =>
  setRules([...rules.value, { type, ...RULE_DEFAULTS[type] }]);
const removeRule = index => setRules(rules.value.filter((_, i) => i !== index));
const patchRule = (index, patch) =>
  setRules(rules.value.map((r, i) => (i === index ? { ...r, ...patch } : r)));

const toggleIn = (list, value) =>
  (list || []).includes(value)
    ? list.filter(v => v !== value)
    : [...(list || []), value];

const needsValue = operator => !['present', 'blank'].includes(operator);
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="condition-editor">
    <div class="flex items-center gap-2">
      <span :class="LABEL_CLASS">{{
        t('CHATFLOW.EDITOR.CONDITION.MATCH')
      }}</span>
      <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1">
        <button
          v-for="item in ['all', 'any']"
          :key="item"
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md transition-colors"
          :class="
            (config.match || 'all') === item
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="emit('update', { match: item })"
        >
          {{ t(`CHATFLOW.EDITOR.CONDITION.MATCH_${item.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <p v-if="!rules.length" :class="HINT_CLASS">
      {{ t('CHATFLOW.EDITOR.CONDITION.EMPTY') }}
    </p>

    <div
      v-for="(rule, index) in rules"
      :key="index"
      class="flex flex-col gap-2 p-3 rounded-xl border border-n-weak bg-n-alpha-1"
      :data-testid="`condition-rule-${rule.type}`"
    >
      <div class="flex items-center justify-between">
        <span class="text-xs font-semibold text-n-slate-12">
          {{ t(`CHATFLOW.EDITOR.CONDITION.TYPES.${rule.type.toUpperCase()}`) }}
        </span>
        <Button
          variant="ghost"
          color="ruby"
          size="xs"
          icon="i-lucide-x"
          @click="removeRule(index)"
        />
      </div>

      <template v-if="rule.type === 'label'">
        <select
          :value="rule.operator"
          :class="INPUT_CLASS"
          @change="patchRule(index, { operator: $event.target.value })"
        >
          <option value="has">{{ t('CHATFLOW.EDITOR.CONDITION.HAS') }}</option>
          <option value="not_has">
            {{ t('CHATFLOW.EDITOR.CONDITION.NOT_HAS') }}
          </option>
        </select>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="label in labels"
            :key="label.id"
            type="button"
            class="flex items-center gap-1.5 px-2 h-7 rounded-md border text-xs cursor-pointer"
            :class="chipClass((rule.label_ids || []).includes(label.id))"
            @click="
              patchRule(index, {
                label_ids: toggleIn(rule.label_ids, label.id),
              })
            "
          >
            <span
              class="size-2 rounded-full"
              :style="{ backgroundColor: label.color }"
            />
            {{ label.title }}
          </button>
        </div>
      </template>

      <template v-else-if="rule.type === 'attribute'">
        <div class="grid grid-cols-2 gap-2">
          <select
            :value="rule.scope"
            :class="INPUT_CLASS"
            @change="patchRule(index, { scope: $event.target.value })"
          >
            <option value="contact">
              {{ t('CHATFLOW.EDITOR.QUESTION.SCOPE.CONTACT') }}
            </option>
            <option value="conversation">
              {{ t('CHATFLOW.EDITOR.QUESTION.SCOPE.CONVERSATION') }}
            </option>
          </select>
          <input
            :value="rule.key"
            type="text"
            :placeholder="t('CHATFLOW.EDITOR.CONDITION.KEY')"
            :class="INPUT_CLASS"
            @change="patchRule(index, { key: $event.target.value.trim() })"
          />
        </div>
        <div class="grid grid-cols-2 gap-2">
          <select
            :value="rule.operator"
            :class="INPUT_CLASS"
            @change="patchRule(index, { operator: $event.target.value })"
          >
            <option v-for="op in OPERATORS" :key="op" :value="op">
              {{ t(`CHATFLOW.EDITOR.CONDITION.OPERATORS.${op.toUpperCase()}`) }}
            </option>
          </select>
          <input
            v-if="needsValue(rule.operator)"
            :value="rule.value"
            type="text"
            :placeholder="t('CHATFLOW.EDITOR.CONDITION.VALUE')"
            :class="INPUT_CLASS"
            @input="patchRule(index, { value: $event.target.value })"
          />
        </div>
      </template>

      <select
        v-else-if="rule.type === 'lead_source'"
        :value="rule.value"
        :class="INPUT_CLASS"
        @change="patchRule(index, { value: $event.target.value })"
      >
        <option value="anuncio_facebook">
          {{ t('CHATFLOW.EDITOR.CONDITION.SOURCE_AD') }}
        </option>
        <option value="organico">
          {{ t('CHATFLOW.EDITOR.CONDITION.SOURCE_ORGANIC') }}
        </option>
      </select>

      <select
        v-else-if="rule.type === 'recurring'"
        :value="String(rule.value)"
        :class="INPUT_CLASS"
        @change="patchRule(index, { value: $event.target.value === 'true' })"
      >
        <option value="true">
          {{ t('CHATFLOW.EDITOR.CONDITION.RECURRING_YES') }}
        </option>
        <option value="false">
          {{ t('CHATFLOW.EDITOR.CONDITION.RECURRING_NO') }}
        </option>
      </select>

      <select
        v-else-if="rule.type === 'business_hours'"
        :value="rule.value"
        :class="INPUT_CLASS"
        @change="patchRule(index, { value: $event.target.value })"
      >
        <option value="open">{{ t('CHATFLOW.EDITOR.CONDITION.OPEN') }}</option>
        <option value="closed">
          {{ t('CHATFLOW.EDITOR.CONDITION.CLOSED') }}
        </option>
      </select>

      <template v-else-if="rule.type === 'schedule'">
        <div class="flex gap-1">
          <button
            v-for="day in WEEKDAYS"
            :key="day"
            type="button"
            class="flex-1 h-7 rounded-md border text-[11px] font-medium cursor-pointer"
            :class="chipClass((rule.weekdays || []).includes(day))"
            @click="
              patchRule(index, { weekdays: toggleIn(rule.weekdays, day) })
            "
          >
            {{ t(`CHATFLOW.EDITOR.WEEKDAYS.D${day}`) }}
          </button>
        </div>
        <div class="flex items-center gap-2 text-xs text-n-slate-11">
          <input
            :value="rule.from"
            type="time"
            :class="INPUT_CLASS"
            @change="patchRule(index, { from: $event.target.value })"
          />
          {{ t('CHATFLOW.EDITOR.CONDITION.TO') }}
          <input
            :value="rule.to"
            type="time"
            :class="INPUT_CLASS"
            @change="patchRule(index, { to: $event.target.value })"
          />
        </div>
      </template>
    </div>

    <div class="flex flex-col gap-1.5">
      <span :class="LABEL_CLASS">{{ t('CHATFLOW.EDITOR.CONDITION.ADD') }}</span>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="type in RULE_TYPES"
          :key="type"
          type="button"
          class="px-2.5 h-7 rounded-md border border-dashed border-n-weak text-xs text-n-slate-11 hover:border-n-teal-7 hover:text-n-teal-11 cursor-pointer"
          :data-testid="`condition-add-${type}`"
          @click="addRule(type)"
        >
          + {{ t(`CHATFLOW.EDITOR.CONDITION.TYPES.${type.toUpperCase()}`) }}
        </button>
      </div>
    </div>
  </div>
</template>
