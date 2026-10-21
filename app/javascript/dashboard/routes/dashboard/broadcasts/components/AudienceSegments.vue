<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Segmentos que ESTREITAM o público: sozinhos filtram a base inteira; junto
// das etiquetas/listas filtram o que elas trouxeram. Ex.: "recorrentes que
// não respondem há 60 dias", "aniversariantes da semana vindas de anúncio".
const props = defineProps({
  modelValue: { type: Object, required: true },
  labels: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const ORIGINS = ['anuncio_facebook', 'organico'];
const RECURRING = ['', 'yes', 'no'];
const BIRTHDAYS = ['', 'today', 'week', 'month'];

const audience = computed(() => props.modelValue);

const set = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });

const toggleIn = (key, value) => {
  const list = [...(audience.value[key] || [])];
  const index = list.indexOf(value);
  if (index === -1) list.push(value);
  else list.splice(index, 1);
  set(key, list);
};

const isOn = (key, value) => (audience.value[key] || []).includes(value);

const chipClass = active =>
  active
    ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
    : 'border-n-weak text-n-slate-11 hover:border-n-slate-8';

const fieldClass =
  'h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 !mb-0';
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="audience-segments">
    <p class="m-0 text-[11px] text-n-slate-10">
      {{ t('BROADCAST.SEGMENTS.HINT') }}
    </p>

    <div class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('BROADCAST.SEGMENTS.ORIGIN') }}
      </span>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="origin in ORIGINS"
          :key="origin"
          type="button"
          class="px-3 h-8 rounded-full border text-xs transition-colors"
          :class="chipClass(isOn('origins', origin))"
          :data-testid="`segment-origin-${origin}`"
          @click="toggleIn('origins', origin)"
        >
          {{ t(`BROADCAST.SEGMENTS.ORIGINS.${origin.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('BROADCAST.SEGMENTS.RECURRING') }}
        </span>
        <select
          :value="audience.recurring || ''"
          :class="fieldClass"
          data-testid="segment-recurring"
          @change="set('recurring', $event.target.value)"
        >
          <option v-for="option in RECURRING" :key="option" :value="option">
            {{
              t(
                `BROADCAST.SEGMENTS.RECURRING_OPTIONS.${(option || 'any').toUpperCase()}`
              )
            }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('BROADCAST.SEGMENTS.NO_REPLY_DAYS') }}
        </span>
        <input
          :value="audience.no_reply_days || ''"
          type="number"
          min="0"
          :placeholder="t('BROADCAST.SEGMENTS.NO_REPLY_PLACEHOLDER')"
          :class="fieldClass"
          data-testid="segment-no-reply"
          @input="set('no_reply_days', Number($event.target.value) || '')"
        />
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('BROADCAST.SEGMENTS.BIRTHDAY') }}
        </span>
        <select
          :value="audience.birthday || ''"
          :class="fieldClass"
          data-testid="segment-birthday"
          @change="set('birthday', $event.target.value)"
        >
          <option v-for="option in BIRTHDAYS" :key="option" :value="option">
            {{
              t(
                `BROADCAST.SEGMENTS.BIRTHDAY_OPTIONS.${(option || 'any').toUpperCase()}`
              )
            }}
          </option>
        </select>
      </label>
    </div>

    <div v-if="labels.length" class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('BROADCAST.SEGMENTS.EXCLUDE_LABELS') }}
      </span>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="label in labels"
          :key="label.id"
          type="button"
          class="px-3 h-7 rounded-full border text-xs transition-colors"
          :class="
            isOn('exclude_label_ids', label.id)
              ? 'border-n-ruby-8 bg-n-ruby-3 text-n-ruby-11'
              : 'border-n-weak text-n-slate-11 hover:border-n-slate-8'
          "
          @click="toggleIn('exclude_label_ids', label.id)"
        >
          {{ label.title }}
        </button>
      </div>
    </div>
  </div>
</template>
