<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEmitter } from 'dashboard/composables/emitter';
import ConversationAPI from 'dashboard/api/inbox/conversation';

// UniverZAP: the agenda of the conversation list — pick the day conversations
// started on and walk through the days like a calendar. Folded, it is one
// line (‹ day ›, how many started that day, clear); unfolded, a week of days
// each with its count, so the busy days show at a glance. The counts follow
// the view on screen (status, tab, inbox, label…), the badges never change.
const props = defineProps({
  // 'YYYY-MM-DD' in the agent's timezone, or null for every day.
  modelValue: { type: String, default: null },
  // The list's own filters, so the counts match what the list shows.
  scope: { type: Object, required: true },
  expanded: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'toggle']);

const { t, locale } = useI18n();

const WEEK = 7;

// The app's locales are pt_BR-style; Intl only takes pt-BR.
const dateLocale = computed(() => locale.value.replace('_', '-'));

const pad = n => String(n).padStart(2, '0');
const toKey = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const fromKey = key => {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
};
const addDays = (key, days) => {
  const date = fromKey(key);
  date.setDate(date.getDate() + days);
  return toKey(date);
};

const todayKey = ref(toKey(new Date()));
const counts = ref({});

// The week on screen ends at the picked day + 3 (so it sits in the middle),
// never after today: there is nothing to see in the future.
const windowEnd = computed(() => {
  if (!props.modelValue) return todayKey.value;
  const end = addDays(props.modelValue, 3);
  return end > todayKey.value ? todayKey.value : end;
});

const days = computed(() =>
  Array.from({ length: WEEK }, (_, i) => {
    const key = addDays(windowEnd.value, i - (WEEK - 1));
    const date = fromKey(key);
    return {
      key,
      weekday: date.toLocaleDateString(dateLocale.value, { weekday: 'short' }),
      day: date.getDate(),
      count: counts.value[key] || 0,
      isToday: key === todayKey.value,
    };
  })
);

const label = computed(() => {
  if (!props.modelValue) return t('CHAT_LIST.DATES.ALL');
  if (props.modelValue === todayKey.value) return t('CHAT_LIST.DATES.TODAY');
  if (props.modelValue === addDays(todayKey.value, -1)) {
    return t('CHAT_LIST.DATES.YESTERDAY');
  }
  return fromKey(props.modelValue).toLocaleDateString(dateLocale.value, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
});

const selectedCount = computed(() =>
  props.modelValue ? counts.value[props.modelValue] || 0 : null
);

const canGoForward = computed(
  () => !!props.modelValue && props.modelValue < todayKey.value
);

const select = key =>
  emit('update:modelValue', key === props.modelValue ? null : key);

// ‹ from "every day" starts the walk at today; › past today goes back to
// every day, so the arrows alone are enough to use the whole agenda.
const step = delta => {
  if (!props.modelValue) {
    emit('update:modelValue', todayKey.value);
    return;
  }
  const next = addDays(props.modelValue, delta);
  emit('update:modelValue', next > todayKey.value ? null : next);
};

const onPick = event => {
  const { value } = event.target;
  if (value) emit('update:modelValue', value > todayKey.value ? null : value);
};

let lastFetch = 0;
async function fetchCounts(force = true) {
  if (!force && Date.now() - lastFetch < 30000) return;
  lastFetch = Date.now();
  todayKey.value = toKey(new Date());
  const from = addDays(windowEnd.value, -(WEEK - 1));
  try {
    const { data } = await ConversationAPI.createdPerDay({
      ...props.scope,
      from,
      to: windowEnd.value,
    });
    counts.value = data.days || {};
  } catch {
    counts.value = {};
  }
}

watch(
  () => [windowEnd.value, JSON.stringify(props.scope)],
  () => fetchCounts(),
  { immediate: true }
);
useEmitter('fetch_conversation_stats', () => fetchCounts(false));
</script>

<template>
  <div class="px-3 py-1 border-b border-n-weak">
    <div class="flex items-center gap-1 text-xs text-n-slate-11">
      <span class="i-lucide-calendar-days size-3.5 shrink-0" />
      <span class="shrink-0">{{ $t('CHAT_LIST.DATES.TITLE') }}</span>
      <button
        type="button"
        class="grid rounded size-5 place-items-center hover:bg-n-alpha-2"
        :title="$t('CHAT_LIST.DATES.PREVIOUS')"
        @click="step(-1)"
      >
        <span class="i-lucide-chevron-left size-3.5" />
      </button>
      <button
        type="button"
        class="px-1 font-medium truncate rounded text-n-slate-12 hover:bg-n-alpha-2"
        :title="$t('CHAT_LIST.DATES.TOGGLE')"
        :aria-expanded="expanded"
        @click="emit('toggle')"
      >
        {{ label }}
      </button>
      <button
        type="button"
        class="grid rounded size-5 place-items-center hover:bg-n-alpha-2 disabled:opacity-40"
        :title="$t('CHAT_LIST.DATES.NEXT')"
        :disabled="!canGoForward"
        @click="step(1)"
      >
        <span class="i-lucide-chevron-right size-3.5" />
      </button>
      <span v-if="selectedCount !== null" class="tabular-nums text-n-slate-10">
        {{
          $t('CHAT_LIST.DATES.STARTED', { count: selectedCount }, selectedCount)
        }}
      </span>
      <button
        v-if="modelValue"
        type="button"
        class="grid rounded size-5 place-items-center hover:bg-n-alpha-2"
        :title="$t('CHAT_LIST.DATES.CLEAR')"
        @click="emit('update:modelValue', null)"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
      <label
        class="relative grid ml-auto rounded cursor-pointer size-5 place-items-center hover:bg-n-alpha-2"
        :title="$t('CHAT_LIST.DATES.PICK')"
      >
        <span class="i-lucide-calendar-search size-3.5" />
        <input
          type="date"
          class="absolute inset-0 opacity-0 cursor-pointer"
          :max="todayKey"
          :value="modelValue || ''"
          @change="onPick"
        />
      </label>
      <button
        type="button"
        class="grid rounded size-5 place-items-center hover:bg-n-alpha-2"
        :title="$t('CHAT_LIST.DATES.TOGGLE')"
        :aria-expanded="expanded"
        @click="emit('toggle')"
      >
        <span
          class="size-3.5"
          :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>
    </div>

    <ul v-if="expanded" class="grid grid-cols-7 gap-1 pt-1 mb-0 list-none">
      <li v-for="item in days" :key="item.key">
        <button
          type="button"
          class="flex flex-col items-center w-full py-1 rounded-lg border transition-colors"
          :class="
            item.key === modelValue
              ? 'bg-n-teal-3 border-n-teal-7 text-n-teal-11'
              : 'bg-n-alpha-1 border-transparent text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="select(item.key)"
        >
          <span class="text-[10px] leading-tight capitalize">
            {{ item.weekday }}
          </span>
          <span
            class="text-sm font-semibold leading-tight tabular-nums"
            :class="
              item.isToday && item.key !== modelValue ? 'text-n-teal-11' : ''
            "
          >
            {{ item.day }}
          </span>
          <span
            class="text-[10px] leading-tight tabular-nums"
            :class="item.count ? 'text-n-slate-12' : 'text-n-slate-9'"
          >
            {{ item.count }}
          </span>
        </button>
      </li>
    </ul>
  </div>
</template>
