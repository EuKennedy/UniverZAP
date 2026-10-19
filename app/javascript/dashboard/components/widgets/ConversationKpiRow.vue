<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';
import { formatSeconds } from 'dashboard/routes/dashboard/settings/reports/components/panel/panelFormat';

// UniverZAP: the glanceable layer of the conversation list — the four
// counters a reception needs to triage the day, as cards instead of a pill
// trail. Same views and same numbers the Todos dropdown already carries,
// nothing extra is fetched; clicking a card is clicking that view.
const props = defineProps({
  items: { type: Array, required: true },
  activeKey: { type: String, required: true },
  // Today's first-reply figures from the Painel endpoint: { median, replied,
  // created } — median seconds (null until something is replied), how many of
  // today's conversations were replied, how many were created. Undefined
  // while not loaded, which hides the line.
  firstReply: { type: Object, default: undefined },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const firstReplyLabel = computed(() =>
  props.firstReply?.median == null
    ? '—'
    : formatSeconds(props.firstReply.median, t)
);

// Today's base: how many were answered, and the actionable rest nobody has.
const firstReplyCount = computed(() =>
  props.firstReply?.created
    ? t('CHAT_LIST.KPI_FIRST_REPLY_PENDING', {
        replied: props.firstReply.replied,
        pending: props.firstReply.created - props.firstReply.replied,
      })
    : t('CHAT_LIST.KPI_FIRST_REPLY_NONE')
);

// Aguardando is the fila de risco: a non-zero count is the one number that
// should pull the eye, so it alone gets the warning tone.
const isRisk = item =>
  item.key === wootConstants.LIST_VIEW.WAITING && item.count > 0;
</script>

<template>
  <ul class="grid grid-cols-2 gap-1.5 px-3 pt-1.5 pb-0 mb-0 list-none">
    <li v-for="item in items" :key="item.key">
      <button
        type="button"
        class="flex flex-col items-start w-full gap-0.5 px-2.5 py-1.5 text-start rounded-lg border transition-colors"
        :class="
          item.key === activeKey
            ? 'bg-n-teal-3 border-n-teal-7 text-n-teal-11'
            : 'bg-n-alpha-1 border-transparent text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="emit('select', item.key)"
      >
        <span class="text-xs leading-tight truncate w-full">
          {{ item.name }}
        </span>
        <span
          class="text-lg font-semibold leading-none tabular-nums"
          :class="
            isRisk(item) && item.key !== activeKey
              ? 'text-n-amber-11'
              : 'text-n-slate-12'
          "
        >
          {{ item.count }}
        </span>
      </button>
    </li>
  </ul>
  <p
    v-if="firstReply !== undefined"
    class="flex items-center flex-wrap gap-1 px-3 pt-1.5 pb-0 mb-0 text-xs text-n-slate-11"
    :title="$t('CHAT_LIST.KPI_FIRST_REPLY_HINT')"
  >
    <span class="i-lucide-timer size-3.5" />
    {{ $t('CHAT_LIST.KPI_FIRST_REPLY') }}
    <span class="font-medium text-n-slate-12 tabular-nums">
      {{ firstReplyLabel }}
    </span>
    <span v-if="firstReply?.median != null" class="text-n-slate-10">
      {{ $t('CHAT_LIST.KPI_FIRST_REPLY_MEDIAN') }}
    </span>
    <span class="text-n-slate-10">{{ firstReplyCount }}</span>
  </p>
</template>
