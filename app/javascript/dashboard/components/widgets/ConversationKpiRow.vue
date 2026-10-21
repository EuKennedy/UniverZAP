<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';
import { formatSeconds } from 'dashboard/routes/dashboard/settings/reports/components/panel/panelFormat';

// UniverZAP: the glanceable layer of the conversation list — the four
// counters a reception needs to triage the day, as cards instead of a pill
// trail, under a "Hoje" header that folds the block away. Folded, the header
// still carries the two numbers that matter (first-reply median, unanswered
// today), so the list gains its room without losing the signal. Same views
// and same numbers the Todos dropdown already carries, nothing extra is
// fetched; clicking a card is clicking that view.
const props = defineProps({
  items: { type: Array, required: true },
  activeKey: { type: String, required: true },
  // Today's first-reply figures from the Painel endpoint: { median, replied,
  // created } — median seconds (null until something is replied), how many of
  // today's conversations were replied, how many were created. Undefined
  // while not loaded, which hides the line.
  firstReply: { type: Object, default: undefined },
  collapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'toggle']);

const { t } = useI18n();

// Aguardando is the fila de risco: a non-zero count is the one number that
// should pull the eye, so it alone gets the warning tone.
const isRisk = item =>
  item.key === wootConstants.LIST_VIEW.WAITING && item.count > 0;

const firstReplyLabel = computed(() =>
  props.firstReply?.median == null
    ? '—'
    : formatSeconds(props.firstReply.median, t)
);

const pendingToday = computed(() =>
  props.firstReply?.created
    ? props.firstReply.created - props.firstReply.replied
    : 0
);

// The actionable number: today's conversations nobody answered yet.
const firstReplyCount = computed(() =>
  props.firstReply?.created
    ? t('CHAT_LIST.KPI_FIRST_REPLY_PENDING', {
        replied: props.firstReply.replied,
        pending: pendingToday.value,
      })
    : t('CHAT_LIST.KPI_FIRST_REPLY_NONE')
);

const compactSummary = computed(() =>
  props.firstReply === undefined
    ? ''
    : t('CHAT_LIST.TODAY.COMPACT', {
        time: firstReplyLabel.value,
        pending: pendingToday.value,
      })
);
</script>

<template>
  <div class="px-3 pt-1.5">
    <button
      type="button"
      class="flex items-center w-full gap-2 py-1 text-xs text-n-slate-11 hover:text-n-slate-12"
      :title="$t('CHAT_LIST.TODAY.TOGGLE')"
      :aria-expanded="!collapsed"
      @click="emit('toggle')"
    >
      <span class="font-medium text-n-slate-12">
        {{ $t('CHAT_LIST.TODAY.TITLE') }}
      </span>
      <span v-if="collapsed" class="truncate tabular-nums">
        {{ compactSummary }}
      </span>
      <span
        class="ml-auto size-3.5 transition-transform duration-200"
        :class="collapsed ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'"
      />
    </button>

    <template v-if="!collapsed">
      <ul class="grid grid-cols-2 gap-1.5 mb-0 list-none">
        <!-- An odd count leaves the last card alone on its row: let it take the width. -->
        <li v-for="item in items" :key="item.key" class="odd:last:col-span-2">
          <button
            type="button"
            class="flex flex-col items-start w-full gap-0.5 px-2.5 py-1.5 text-start rounded-lg border transition-colors"
            :class="
              item.key === activeKey
                ? 'bg-brand-gradient-soft border-n-teal-7 text-n-teal-11'
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
        class="flex items-center flex-wrap gap-1 pt-1.5 mb-0 text-xs text-n-slate-11"
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
  </div>
</template>
