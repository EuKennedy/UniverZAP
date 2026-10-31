<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNumberFormatter } from 'shared/composables/useNumberFormatter';

const props = defineProps({
  stats: { type: Object, default: () => ({}) },
  // Which card matches the filters in place, and whether a card may filter.
  active: { type: String, default: '' },
  interactive: { type: Boolean, default: false },
  recurringAvailable: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
const { formatFullNumber } = useNumberFormatter();

const cards = computed(() => [
  {
    key: 'total',
    icon: 'i-lucide-users',
    tone: 'bg-n-teal-3 text-n-teal-11',
    clickable: false,
  },
  {
    key: 'recent',
    icon: 'i-lucide-user-plus',
    tone: 'bg-n-iris-3 text-n-iris-11',
    clickable: true,
  },
  {
    key: 'recurring',
    icon: 'i-lucide-repeat',
    tone: 'bg-n-amber-3 text-n-amber-11',
    clickable: props.recurringAvailable,
  },
  {
    key: 'withoutPhone',
    stat: 'without_phone',
    icon: 'i-lucide-phone-off',
    tone: 'bg-n-ruby-3 text-n-ruby-11',
    clickable: true,
  },
]);

const valueOf = card => {
  const value = props.stats[card.stat || card.key];
  return value === undefined ? '–' : formatFullNumber(value);
};
const canClick = card => props.interactive && card.clickable;
</script>

<template>
  <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
    <component
      :is="canClick(card) ? 'button' : 'div'"
      v-for="card in cards"
      :key="card.key"
      class="flex items-center gap-3 p-3 text-start transition rounded-xl outline outline-1 -outline-offset-1 bg-n-solid-2"
      :class="[
        active === card.key
          ? 'outline-n-teal-7 shadow-[0_0_20px_-8px_rgba(20,230,127,0.65)]'
          : 'outline-n-weak',
        canClick(card) ? 'hover:outline-n-strong' : '',
      ]"
      @click="canClick(card) && emit('select', card.key)"
    >
      <span
        class="flex items-center justify-center flex-shrink-0 rounded-lg size-9"
        :class="card.tone"
      >
        <span class="size-[18px]" :class="card.icon" />
      </span>
      <span class="min-w-0">
        <span
          class="block text-[11px] font-semibold tracking-wide uppercase truncate text-n-slate-10"
        >
          {{ t(`CONTACTS_LAYOUT.STATS.${card.key.toUpperCase()}`) }}
        </span>
        <span class="block text-lg font-semibold text-n-slate-12 tabular-nums">
          {{ valueOf(card) }}
        </span>
      </span>
    </component>
  </div>
</template>
