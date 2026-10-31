<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';
import { formatSeconds } from 'dashboard/routes/dashboard/settings/reports/components/panel/panelFormat';

// UniverZAP: the glanceable layer of the conversation list — the counters a
// reception needs to triage the day, as glass cards instead of a pill
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

// Each queue keeps its colour and icon, so the eye finds it without reading.
const CARD_LOOK = {
  waiting: { icon: 'i-lucide-hourglass', tone: 'text-n-amber-11' },
  in_attendance: { icon: 'i-lucide-messages-square', tone: 'text-n-teal-11' },
  unassigned: { icon: 'i-lucide-user-round-x', tone: 'text-n-iris-11' },
  resolved: { icon: 'i-lucide-circle-check', tone: 'text-n-teal-11' },
  awaiting_customer: { icon: 'i-lucide-reply', tone: 'text-n-iris-11' },
  scheduled: { icon: 'i-lucide-calendar-check', tone: 'text-n-amber-11' },
};

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
  <div class="relative px-3 pt-1.5">
    <span
      class="absolute top-0 rounded-full pointer-events-none start-1/4 size-40 bg-brand-gradient opacity-[0.12] blur-3xl"
    />
    <button
      type="button"
      class="relative flex items-center w-full gap-2 py-1 text-xs text-n-slate-11 hover:text-n-slate-12"
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
      <ul class="relative grid grid-cols-2 gap-1.5 mb-0 list-none">
        <!-- An odd count leaves the last card alone on its row: let it take the width. -->
        <li v-for="item in items" :key="item.key" class="odd:last:col-span-2">
          <button
            type="button"
            class="relative flex flex-col items-start w-full gap-1 px-2.5 py-2 overflow-hidden text-start transition-all duration-200 border rounded-xl backdrop-blur-xl shadow-[inset_0_1px_0_0_rgba(255,255,255,0.08)] motion-safe:hover:-translate-y-px motion-safe:active:scale-[0.98]"
            :class="
              item.key === activeKey
                ? 'bg-brand-gradient-soft border-n-teal-7 text-n-teal-11 shadow-[0_0_22px_-8px_rgba(20,230,127,0.75)]'
                : 'bg-n-alpha-1 border-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-2 hover:border-n-alpha-3'
            "
            @click="emit('select', item.key)"
          >
            <span
              class="flex items-center w-full gap-1.5 text-xs leading-tight"
            >
              <span
                class="size-3.5 shrink-0"
                :class="[CARD_LOOK[item.key]?.icon, CARD_LOOK[item.key]?.tone]"
              />
              <span class="min-w-0 truncate">{{ item.name }}</span>
              <span
                v-if="isRisk(item)"
                class="rounded-full ms-auto size-1.5 shrink-0 bg-n-amber-9 motion-safe:animate-pulse"
              />
            </span>
            <span
              class="text-xl font-semibold leading-none tabular-nums"
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
        class="relative flex items-center flex-wrap gap-1 pt-1.5 mb-0 text-xs text-n-slate-11"
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
