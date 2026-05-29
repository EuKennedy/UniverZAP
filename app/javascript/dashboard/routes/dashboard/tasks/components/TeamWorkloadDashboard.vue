<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const emit = defineEmits(['focusAgent']);

const { t } = useI18n();
const store = useStore();

const totals = ref({ open: 0, overdue: 0, due_today: 0 });
const agents = ref([]);
const isLoading = ref(false);

const refresh = async () => {
  isLoading.value = true;
  try {
    const payload = await store.dispatch('tasks/fetchTeamWorkload');
    totals.value = payload?.totals || totals.value;
    agents.value = payload?.agents || [];
  } finally {
    isLoading.value = false;
  }
};

const averageOpen = computed(() => {
  if (!agents.value.length) return 0;
  const sum = agents.value.reduce((acc, a) => acc + (a.open_count || 0), 0);
  return Math.round((sum / agents.value.length) * 10) / 10;
});

const maxOpen = computed(() =>
  agents.value.reduce((max, a) => Math.max(max, a.open_count || 0), 1)
);

const STATS = computed(() => [
  {
    key: 'open',
    labelKey: 'TASKS.WORKLOAD.STATS.OPEN',
    value: totals.value.open,
    tone: 'bg-n-blue-3 text-n-blue-12 ring-n-blue-6',
  },
  {
    key: 'overdue',
    labelKey: 'TASKS.WORKLOAD.STATS.OVERDUE',
    value: totals.value.overdue,
    tone: 'bg-n-ruby-3 text-n-ruby-12 ring-n-ruby-6',
  },
  {
    key: 'due_today',
    labelKey: 'TASKS.WORKLOAD.STATS.DUE_TODAY',
    value: totals.value.due_today,
    tone: 'bg-n-amber-3 text-n-amber-12 ring-n-amber-6',
  },
  {
    key: 'avg',
    labelKey: 'TASKS.WORKLOAD.STATS.AVERAGE',
    value: averageOpen.value,
    tone: 'bg-n-teal-3 text-n-teal-12 ring-n-teal-6',
  },
]);

onMounted(refresh);
</script>

<template>
  <section
    class="flex flex-col gap-5 px-6 py-6 overflow-y-auto"
    data-test-id="team-workload-dashboard"
  >
    <header class="flex items-center justify-between">
      <div>
        <h2 class="text-[15px] font-semibold text-n-slate-12 tracking-tight">
          {{ t('TASKS.WORKLOAD.TITLE') }}
        </h2>
        <p class="text-[12px] text-n-slate-10">
          {{ t('TASKS.WORKLOAD.SUBTITLE') }}
        </p>
      </div>
      <button
        type="button"
        class="text-[12px] h-8 px-3 rounded-md ring-1 ring-inset ring-n-weak hover:ring-n-slate-7 text-n-slate-11 hover:text-n-slate-12"
        data-test-id="team-workload-refresh"
        @click="refresh"
      >
        {{ t('TASKS.REFRESH') }}
      </button>
    </header>

    <div
      class="grid grid-cols-2 md:grid-cols-4 gap-3"
      data-test-id="team-workload-stats"
    >
      <article
        v-for="stat in STATS"
        :key="stat.key"
        class="rounded-xl px-4 py-3 ring-1 ring-inset"
        :class="[stat.tone]"
        :data-test-id="`team-workload-stat-${stat.key}`"
      >
        <p class="text-[11px] uppercase tracking-wide opacity-80">
          {{ t(stat.labelKey) }}
        </p>
        <p class="text-2xl font-semibold tabular-nums">{{ stat.value }}</p>
      </article>
    </div>

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-10 text-n-slate-10"
    >
      <span class="i-lucide-loader-circle size-5 animate-spin" />
    </div>

    <div
      v-else-if="!agents.length"
      class="text-center py-10 text-n-slate-10 text-sm"
    >
      {{ t('TASKS.WORKLOAD.EMPTY') }}
    </div>

    <div
      v-else
      class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3"
      data-test-id="team-workload-grid"
    >
      <button
        v-for="row in agents"
        :key="row.user.id"
        type="button"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-1 ring-1 ring-n-weak hover:ring-n-slate-7 text-left transition"
        :data-test-id="`team-workload-card-${row.user.id}`"
        @click="emit('focusAgent', row.user.id)"
      >
        <header class="flex items-center gap-3">
          <Avatar
            :name="row.user.name"
            :src="row.user.avatar_url"
            :size="40"
            rounded-full
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ row.user.name }}
            </p>
            <p class="text-[11px] text-n-slate-10">
              {{ t('TASKS.WORKLOAD.OPEN_COUNT', { n: row.open_count }) }}
            </p>
          </div>
        </header>

        <div
          class="h-1.5 w-full bg-n-alpha-1 rounded-full overflow-hidden"
          :aria-label="t('TASKS.WORKLOAD.LOAD_BAR')"
        >
          <span
            class="block h-full bg-n-blue-9"
            :style="{
              width: `${Math.round((row.open_count / maxOpen) * 100)}%`,
            }"
          />
        </div>

        <dl class="grid grid-cols-3 gap-2 text-[11px]">
          <div>
            <dt class="text-n-slate-10 uppercase tracking-wide">
              {{ t('TASKS.WORKLOAD.LABELS.OVERDUE') }}
            </dt>
            <dd class="tabular-nums text-n-ruby-11">
              {{ row.overdue_count }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-10 uppercase tracking-wide">
              {{ t('TASKS.WORKLOAD.LABELS.TODAY') }}
            </dt>
            <dd class="tabular-nums text-n-amber-11">
              {{ row.due_today_count }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-10 uppercase tracking-wide">
              {{ t('TASKS.WORKLOAD.LABELS.DONE_WEEK') }}
            </dt>
            <dd class="tabular-nums text-n-teal-11">
              {{ row.completed_this_week }}
            </dd>
          </div>
        </dl>
      </button>
    </div>
  </section>
</template>
