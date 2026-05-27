<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import {
  format,
  formatDistanceToNowStrict,
  fromUnixTime,
  isPast,
  isToday,
} from 'date-fns';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';

// Read-only "peek" at every funnel without leaving the conversation. Same
// xlarge frame as the attach modal so the operator can hop between move +
// view without losing visual rhythm. No drag, no edit, no destructive
// actions — pure observability. Loads tasks lazily on funnel selection so
// opening the modal stays cheap.
const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const funnels = computed(() => getters['funnels/getFunnels'].value || []);
const selectedFunnelId = ref(null);
const isLoadingFunnels = ref(false);
const isLoadingTasks = ref(false);

const selectedFunnel = computed(
  () => funnels.value.find(f => f.id === selectedFunnelId.value) || null
);

const stages = computed(() => {
  const list = selectedFunnel.value?.stages || [];
  return [...list].sort((a, b) => a.position - b.position);
});

const tasksByStage = stageId =>
  getters['kanbanTasks/getTasksByStage'].value(
    Number(selectedFunnelId.value),
    Number(stageId)
  ) || [];

const close = () => emit('close');

const ensureFunnelsLoaded = async () => {
  if (funnels.value.length) {
    if (!selectedFunnelId.value) selectedFunnelId.value = funnels.value[0].id;
    return;
  }
  isLoadingFunnels.value = true;
  try {
    await store.dispatch('funnels/get');
    if (funnels.value.length && !selectedFunnelId.value) {
      selectedFunnelId.value = funnels.value[0].id;
    }
  } finally {
    isLoadingFunnels.value = false;
  }
};

const loadTasksForCurrentFunnel = async () => {
  if (!selectedFunnelId.value) return;
  isLoadingTasks.value = true;
  try {
    await store.dispatch(
      'kanbanTasks/getByFunnel',
      Number(selectedFunnelId.value)
    );
  } finally {
    isLoadingTasks.value = false;
  }
};

onMounted(ensureFunnelsLoaded);
watch(
  () => props.show,
  async v => {
    if (!v) return;
    await ensureFunnelsLoaded();
    await loadTasksForCurrentFunnel();
  }
);
watch(selectedFunnelId, () => {
  if (props.show) loadTasksForCurrentFunnel();
});

const stageGradient = stage => {
  const base = stage?.color || '#6366f1';
  return `linear-gradient(180deg, ${base}1a 0%, ${base}05 100%)`;
};

// Compact card meta — viewer mode only shows what's instantly useful:
// title, primary contact, due chip, priority dot. Click is a noop because
// the modal exists to *observe* the pipeline, not navigate away.
const dueMeta = task => {
  if (!task.due_date) return null;
  const date = fromUnixTime(task.due_date);
  const overdue = !task.completed_at && isPast(date) && !isToday(date);
  let label;
  if (isToday(date)) label = t('KANBAN.CARD.DUE_TODAY');
  else if (overdue) {
    label = formatDistanceToNowStrict(date, {
      addSuffix: true,
      unit: 'day',
    });
  } else label = format(date, 'MMM d');
  return { label, overdue };
};

const PRIORITY_DOT = {
  none: null,
  low: 'bg-n-slate-9',
  medium: 'bg-n-blue-9',
  high: 'bg-n-amber-9',
  urgent: 'bg-n-ruby-9',
};

const stageTasksWithMeta = stageId =>
  tasksByStage(stageId).map(task => ({
    ...task,
    contact: (task.contacts || [])[0] || null,
    due: dueMeta(task),
    priorityDot: PRIORITY_DOT[task.priority] || null,
  }));

const totalTasks = computed(() =>
  stages.value.reduce((acc, s) => acc + tasksByStage(s.id).length, 0)
);
</script>

<template>
  <woot-modal
    :show="props.show"
    size="xlarge"
    :on-close="close"
    @update:show="value => !value && close()"
  >
    <div class="flex flex-col h-full w-full bg-n-background text-n-slate-12">
      <!-- HEADER -->
      <header
        class="relative flex items-center justify-between flex-shrink-0 gap-6 px-8 py-5 border-b border-n-weak bg-gradient-to-b from-n-alpha-1 to-transparent"
      >
        <div class="flex items-center gap-4 min-w-0">
          <div
            class="size-11 rounded-xl bg-gradient-to-br from-n-teal-9 to-n-teal-10 flex items-center justify-center shadow-lg shadow-n-teal-9/20 flex-shrink-0"
          >
            <span class="i-lucide-eye size-5 text-white" />
          </div>
          <div class="flex flex-col gap-0.5 min-w-0">
            <h2 class="text-[20px] font-semibold tracking-tight leading-tight">
              {{ t('CONVERSATION.KANBAN_VIEWER.TITLE') }}
            </h2>
            <p class="text-[13px] text-n-slate-11">
              {{ t('CONVERSATION.KANBAN_VIEWER.SUBTITLE') }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="size-9 rounded-lg flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 transition cursor-pointer"
          :aria-label="t('CONVERSATION.KANBAN_VIEWER.CLOSE')"
          @click="close"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>

      <!-- LOADING STATE -->
      <section
        v-if="isLoadingFunnels"
        class="flex-1 flex flex-col items-center justify-center gap-3"
      >
        <span
          class="i-lucide-loader-circle size-6 animate-spin text-n-slate-9"
        />
        <p class="text-sm text-n-slate-11">
          {{ t('CONVERSATION.KANBAN_VIEWER.LOADING') }}
        </p>
      </section>

      <!-- EMPTY STATE -->
      <section
        v-else-if="!funnels.length"
        class="flex-1 flex flex-col items-center justify-center gap-5 px-8 text-center"
      >
        <div
          class="size-16 rounded-2xl bg-n-alpha-1 flex items-center justify-center"
        >
          <span class="i-lucide-layers size-7 text-n-slate-10" />
        </div>
        <div class="flex flex-col gap-1.5 max-w-md">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('CONVERSATION.KANBAN_VIEWER.EMPTY_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-relaxed">
            {{ t('CONVERSATION.KANBAN_VIEWER.EMPTY') }}
          </p>
        </div>
      </section>

      <!-- BOARD -->
      <section v-else class="flex flex-1 min-h-0">
        <!-- Funnel rail -->
        <aside
          class="w-72 flex-shrink-0 border-r border-n-weak overflow-y-auto p-4 flex flex-col gap-1 bg-n-alpha-1"
        >
          <p
            class="text-[10px] uppercase tracking-[0.12em] text-n-slate-10 px-2 pt-1 pb-3 flex items-center justify-between"
          >
            <span>{{ t('CONVERSATION.KANBAN_VIEWER.FUNNELS') }}</span>
            <span class="text-n-slate-9 tabular-nums">{{
              funnels.length
            }}</span>
          </p>
          <button
            v-for="funnel in funnels"
            :key="funnel.id"
            type="button"
            class="group text-left px-3 py-2.5 rounded-lg text-sm transition-all duration-200 relative overflow-hidden cursor-pointer"
            :class="
              funnel.id === selectedFunnelId
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm border border-n-weak'
                : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
            "
            @click="selectedFunnelId = funnel.id"
          >
            <div class="flex items-center gap-2">
              <span
                class="size-1.5 rounded-full flex-shrink-0 transition"
                :class="
                  funnel.id === selectedFunnelId
                    ? 'bg-n-teal-9'
                    : 'bg-n-slate-9 group-hover:bg-n-slate-10'
                "
              />
              <span class="truncate font-medium">{{ funnel.name }}</span>
              <span class="ml-auto text-[10px] text-n-slate-10 tabular-nums">
                {{ (funnel.stages || []).length }}
              </span>
            </div>
            <p
              v-if="funnel.description"
              class="text-[11px] text-n-slate-10 truncate mt-0.5 ml-3.5"
            >
              {{ funnel.description }}
            </p>
          </button>
          <div
            v-if="selectedFunnel"
            class="mt-3 px-3 py-3 rounded-lg bg-n-solid-1/60 border border-n-weak/60"
          >
            <p
              class="text-[10px] uppercase tracking-[0.12em] text-n-slate-10 m-0"
            >
              {{ t('CONVERSATION.KANBAN_VIEWER.SUMMARY') }}
            </p>
            <div class="flex items-baseline gap-1 mt-1">
              <span
                class="text-[22px] font-semibold tabular-nums text-n-slate-12 leading-none"
              >
                {{ totalTasks }}
              </span>
              <span class="text-[11px] text-n-slate-11">
                {{ t('CONVERSATION.KANBAN_VIEWER.TASKS') }}
              </span>
            </div>
          </div>
        </aside>

        <!-- Stages -->
        <main class="flex-1 overflow-x-auto overflow-y-hidden bg-n-background">
          <div
            v-if="isLoadingTasks"
            class="h-full flex items-center justify-center gap-3"
          >
            <span
              class="i-lucide-loader-circle size-5 animate-spin text-n-slate-9"
            />
            <p class="text-sm text-n-slate-11 m-0">
              {{ t('CONVERSATION.KANBAN_VIEWER.LOADING_TASKS') }}
            </p>
          </div>
          <div
            v-else
            class="flex items-stretch gap-4 px-7 py-6 h-full min-w-min"
          >
            <article
              v-for="stage in stages"
              :key="stage.id"
              class="w-[280px] flex-shrink-0 rounded-2xl border border-n-weak flex flex-col overflow-hidden shadow-md shadow-black/10"
              :style="{ background: stageGradient(stage) }"
            >
              <header
                class="flex items-center justify-between px-4 py-3 border-b border-white/5 flex-shrink-0"
              >
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    class="size-2.5 rounded-full flex-shrink-0 ring-2 ring-black/20"
                    :style="{ backgroundColor: stage.color || '#6366f1' }"
                  />
                  <span
                    class="text-[12px] font-semibold text-n-slate-12 truncate tracking-tight"
                  >
                    {{ stage.name }}
                  </span>
                </div>
                <span
                  class="text-[10px] uppercase tracking-wide text-n-slate-10 tabular-nums"
                >
                  {{ tasksByStage(stage.id).length }}
                </span>
              </header>
              <div
                class="flex-1 px-3 py-3 flex flex-col gap-2 overflow-y-auto min-h-0"
              >
                <div
                  v-for="task in stageTasksWithMeta(stage.id)"
                  :key="task.id"
                  class="rounded-lg bg-n-solid-1 ring-1 ring-n-weak p-2.5 flex flex-col gap-1.5"
                >
                  <div class="flex items-start gap-2">
                    <span
                      v-if="task.priorityDot"
                      class="mt-1 size-2 rounded-full flex-shrink-0"
                      :class="task.priorityDot"
                      aria-hidden="true"
                    />
                    <p
                      class="text-[12px] font-semibold text-n-slate-12 m-0 leading-snug line-clamp-2"
                      :class="{ 'line-through opacity-60': task.completed_at }"
                    >
                      {{ task.title }}
                    </p>
                  </div>
                  <div
                    v-if="task.contact || task.due"
                    class="flex items-center justify-between gap-2 mt-0.5"
                  >
                    <div
                      v-if="task.contact"
                      class="flex items-center gap-1.5 min-w-0"
                    >
                      <Avatar
                        :src="task.contact.thumbnail || task.contact.avatar_url"
                        :name="task.contact.name"
                        :size="18"
                        rounded-full
                      />
                      <span
                        class="text-[11px] text-n-slate-11 truncate min-w-0"
                      >
                        {{ task.contact.name }}
                      </span>
                    </div>
                    <span v-else />
                    <span
                      v-if="task.due"
                      class="inline-flex items-center gap-1 text-[10.5px] font-medium tabular-nums"
                      :class="
                        task.due.overdue ? 'text-n-ruby-11' : 'text-n-slate-11'
                      "
                    >
                      <Icon icon="i-lucide-calendar" class="size-3" />
                      {{ task.due.label }}
                    </span>
                  </div>
                </div>
                <div
                  v-if="!tasksByStage(stage.id).length"
                  class="flex flex-col items-center justify-center gap-1 py-6 text-center"
                >
                  <span
                    class="i-lucide-inbox size-5 text-n-slate-9"
                    aria-hidden="true"
                  />
                  <p class="text-[11px] text-n-slate-10 m-0">
                    {{ t('CONVERSATION.KANBAN_VIEWER.STAGE_EMPTY') }}
                  </p>
                </div>
              </div>
            </article>
            <div
              v-if="!stages.length"
              class="flex-1 flex items-center justify-center"
            >
              <p class="text-sm text-n-slate-11">
                {{ t('CONVERSATION.KANBAN_VIEWER.NO_STAGES') }}
              </p>
            </div>
          </div>
        </main>
      </section>
    </div>
  </woot-modal>
</template>
