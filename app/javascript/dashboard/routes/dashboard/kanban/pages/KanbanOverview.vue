<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import FunnelFormModal from '../components/FunnelFormModal.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const funnels = useMapGetter('funnels/getFunnels');
const uiFlags = useMapGetter('funnels/getUIFlags');
const currentUser = useMapGetter('getCurrentUser');

const isAdmin = computed(() => currentUser.value?.role === 'administrator');

const showFunnelModal = ref(false);
const editingFunnel = ref(null);
const search = ref('');

const openCreate = () => {
  editingFunnel.value = null;
  showFunnelModal.value = true;
};

const closeModal = () => {
  showFunnelModal.value = false;
  editingFunnel.value = null;
};

const goToBoard = funnel => {
  router.push(accountScopedRoute('kanban_board', { funnelId: funnel.id }));
};

const goToSettings = (funnel, event) => {
  event.stopPropagation();
  router.push(
    accountScopedRoute('kanban_funnel_settings', { funnelId: funnel.id })
  );
};

const handleSubmit = async payload => {
  try {
    if (editingFunnel.value) {
      await store.dispatch('funnels/update', {
        id: editingFunnel.value.id,
        ...payload,
      });
      useAlert(t('KANBAN.FUNNEL.UPDATE_SUCCESS'));
    } else {
      const created = await store.dispatch('funnels/create', payload);
      useAlert(t('KANBAN.FUNNEL.CREATE_SUCCESS'));
      closeModal();
      router.push(accountScopedRoute('kanban_board', { funnelId: created.id }));
      return;
    }
    closeModal();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.FUNNEL.SAVE_ERROR'));
  }
};

const totalTasks = funnel =>
  funnel.tasks_count ??
  (funnel.stages || []).reduce((acc, s) => acc + (s.tasks_count || 0), 0);

const stagePreview = funnel => (funnel.stages || []).slice(0, 8);

const filteredFunnels = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return funnels.value;
  return funnels.value.filter(
    f =>
      f.name.toLowerCase().includes(q) ||
      (f.description || '').toLowerCase().includes(q)
  );
});

// Global stats across all funnels
const stats = computed(() => {
  const list = funnels.value || [];
  const stages = list.reduce((acc, f) => acc + (f.stages || []).length, 0);
  const tasks = list.reduce((acc, f) => acc + totalTasks(f), 0);
  return {
    funnels: list.length,
    stages,
    tasks,
  };
});

// Funnel-level conversion rate: tasks in won stages / total tasks
const wonRate = funnel => {
  const stages = funnel.stages || [];
  const total = totalTasks(funnel);
  if (!total) return 0;
  const won = stages
    .filter(s => s.status_type === 'won')
    .reduce((acc, s) => acc + (s.tasks_count || 0), 0);
  return Math.round((won / total) * 100);
};

const stageDistribution = funnel => {
  const stages = (funnel.stages || []).filter(s => (s.tasks_count || 0) > 0);
  const total = stages.reduce((acc, s) => acc + (s.tasks_count || 0), 0) || 1;
  return stages.map(s => ({
    id: s.id,
    name: s.name,
    color: s.color,
    pct: ((s.tasks_count || 0) / total) * 100,
  }));
};
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-background">
    <!-- HERO HEADER with stats -->
    <header
      class="flex-shrink-0 px-10 pt-9 pb-7 border-b border-n-weak relative overflow-hidden"
    >
      <div
        class="absolute inset-0 bg-gradient-to-br from-n-iris-9/[0.06] via-transparent to-n-teal-9/[0.04] pointer-events-none"
      />
      <div
        class="absolute -top-24 -right-24 size-72 rounded-full bg-n-iris-9/10 blur-3xl pointer-events-none"
      />

      <div class="relative flex items-start justify-between gap-6 mb-8">
        <div class="flex items-start gap-4 min-w-0">
          <div
            class="size-12 rounded-2xl bg-gradient-to-br from-n-iris-9 to-n-iris-11 flex items-center justify-center shadow-lg shadow-n-iris-9/20 flex-shrink-0"
          >
            <span class="i-lucide-kanban-square size-6 text-white" />
          </div>
          <div class="flex flex-col gap-1 min-w-0">
            <h1
              class="text-[26px] font-semibold text-n-slate-12 tracking-tight leading-tight"
            >
              {{ t('KANBAN.OVERVIEW.TITLE') }}
            </h1>
            <p class="text-[13px] text-n-slate-11 max-w-2xl leading-relaxed">
              {{ t('KANBAN.OVERVIEW.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          v-if="isAdmin"
          icon="i-lucide-plus"
          :label="t('KANBAN.OVERVIEW.NEW_FUNNEL')"
          size="sm"
          solid
          blue
          @click="openCreate"
        />
      </div>

      <!-- Stats row -->
      <div class="relative grid grid-cols-3 gap-4 max-w-3xl">
        <div
          class="flex flex-col gap-1.5 px-5 py-4 rounded-2xl bg-n-solid-1/80 backdrop-blur-md ring-1 ring-n-weak"
        >
          <span
            class="text-[10px] uppercase tracking-[0.12em] text-n-slate-10 font-medium"
          >
            {{ t('KANBAN.OVERVIEW.STATS.FUNNELS') }}
          </span>
          <div class="flex items-baseline gap-2">
            <span
              class="text-3xl font-semibold text-n-slate-12 tabular-nums tracking-tight"
            >
              {{ stats.funnels }}
            </span>
            <span class="i-lucide-folder-kanban size-4 text-n-iris-11" />
          </div>
        </div>
        <div
          class="flex flex-col gap-1.5 px-5 py-4 rounded-2xl bg-n-solid-1/80 backdrop-blur-md ring-1 ring-n-weak"
        >
          <span
            class="text-[10px] uppercase tracking-[0.12em] text-n-slate-10 font-medium"
          >
            {{ t('KANBAN.OVERVIEW.STATS.STAGES') }}
          </span>
          <div class="flex items-baseline gap-2">
            <span
              class="text-3xl font-semibold text-n-slate-12 tabular-nums tracking-tight"
            >
              {{ stats.stages }}
            </span>
            <span class="i-lucide-layers size-4 text-n-blue-11" />
          </div>
        </div>
        <div
          class="flex flex-col gap-1.5 px-5 py-4 rounded-2xl bg-n-solid-1/80 backdrop-blur-md ring-1 ring-n-weak"
        >
          <span
            class="text-[10px] uppercase tracking-[0.12em] text-n-slate-10 font-medium"
          >
            {{ t('KANBAN.OVERVIEW.STATS.TASKS') }}
          </span>
          <div class="flex items-baseline gap-2">
            <span
              class="text-3xl font-semibold text-n-slate-12 tabular-nums tracking-tight"
            >
              {{ stats.tasks }}
            </span>
            <span class="i-lucide-square-check-big size-4 text-n-teal-11" />
          </div>
        </div>
      </div>
    </header>

    <!-- Toolbar -->
    <div
      v-if="funnels.length"
      class="flex-shrink-0 flex items-center gap-3 px-10 py-5"
    >
      <div
        class="flex-1 max-w-md flex items-center gap-2 px-3.5 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus-within:ring-n-slate-7 transition"
      >
        <span class="i-lucide-search size-3.5 text-n-slate-10 flex-shrink-0" />
        <input
          v-model="search"
          type="text"
          :placeholder="t('KANBAN.OVERVIEW.SEARCH_PLACEHOLDER')"
          class="flex-1 bg-transparent outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
        />
        <button
          v-if="search"
          type="button"
          class="size-4 text-n-slate-10 hover:text-n-slate-12"
          @click="search = ''"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <p class="text-[12px] text-n-slate-10 tabular-nums">
        {{ filteredFunnels.length }} / {{ funnels.length }}
      </p>
    </div>

    <!-- Loading -->
    <section
      v-if="uiFlags.isFetching"
      class="flex-1 flex items-center justify-center"
    >
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <!-- Empty -->
    <section
      v-else-if="!funnels.length"
      class="flex-1 flex flex-col items-center justify-center gap-5 px-8 text-center"
    >
      <div
        class="size-20 rounded-3xl bg-gradient-to-br from-n-iris-9/20 to-n-iris-9/[0.04] ring-1 ring-n-weak flex items-center justify-center"
      >
        <span class="i-lucide-kanban-square size-9 text-n-iris-11" />
      </div>
      <div class="flex flex-col gap-2 max-w-md">
        <h2 class="text-xl font-semibold text-n-slate-12 tracking-tight">
          {{ t('KANBAN.OVERVIEW.EMPTY_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11 leading-relaxed">
          {{ t('KANBAN.OVERVIEW.EMPTY_DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-if="isAdmin"
        icon="i-lucide-plus"
        :label="t('KANBAN.OVERVIEW.CREATE_FIRST')"
        size="sm"
        solid
        blue
        @click="openCreate"
      />
    </section>

    <!-- Funnel grid -->
    <section v-else class="px-10 pb-10">
      <div
        class="grid gap-6 [grid-template-columns:repeat(auto-fill,minmax(340px,1fr))]"
      >
        <button
          v-for="funnel in filteredFunnels"
          :key="funnel.id"
          type="button"
          class="funnel-card group relative flex flex-col gap-4 p-5 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak text-left overflow-hidden transition-all duration-200 ease-out hover:ring-n-slate-7 hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(0,0,0,0.35)]"
          @click="goToBoard(funnel)"
        >
          <!-- Top gradient accent -->
          <span
            class="absolute inset-x-0 top-0 h-[3px] bg-gradient-to-r from-n-iris-9 via-n-blue-9 to-n-teal-9 opacity-60 group-hover:opacity-100 transition-opacity"
          />

          <!-- Header: title + settings -->
          <div class="flex items-start justify-between gap-3">
            <div class="flex flex-col gap-1 min-w-0 flex-1">
              <h3
                class="text-[15px] font-semibold text-n-slate-12 line-clamp-2 leading-snug tracking-tight"
              >
                {{ funnel.name }}
              </h3>
              <p
                v-if="funnel.description"
                class="text-[12px] text-n-slate-11 line-clamp-2 leading-relaxed"
              >
                {{ funnel.description }}
              </p>
            </div>
            <span
              v-if="isAdmin"
              role="button"
              tabindex="0"
              class="size-7 rounded-lg grid place-content-center text-n-slate-11 opacity-0 group-hover:opacity-100 hover:bg-n-alpha-2 transition-all flex-shrink-0"
              @click="goToSettings(funnel, $event)"
              @keydown.enter="goToSettings(funnel, $event)"
            >
              <span class="i-lucide-settings-2 size-4" />
            </span>
          </div>

          <!-- Stage distribution bar (proportional) -->
          <div
            v-if="stageDistribution(funnel).length"
            class="flex items-center gap-0.5 h-2 rounded-full overflow-hidden bg-n-alpha-1"
          >
            <span
              v-for="seg in stageDistribution(funnel)"
              :key="seg.id"
              v-tooltip.top="`${seg.name} · ${Math.round(seg.pct)}%`"
              :style="{ width: `${seg.pct}%`, backgroundColor: seg.color }"
              class="h-full transition-all"
            />
          </div>
          <!-- Empty stage rail -->
          <div
            v-else-if="stagePreview(funnel).length"
            class="flex items-center gap-1"
          >
            <span
              v-for="stage in stagePreview(funnel)"
              :key="stage.id"
              class="flex-1 h-1 rounded-full opacity-50"
              :style="{ backgroundColor: stage.color }"
              :title="stage.name"
            />
          </div>

          <!-- Stats footer -->
          <div
            class="flex items-center justify-between gap-4 mt-auto pt-3 border-t border-n-weak"
          >
            <div class="flex items-center gap-4 text-[12px] text-n-slate-11">
              <span class="inline-flex items-center gap-1.5">
                <span class="i-lucide-layers size-3.5 text-n-slate-10" />
                <span class="tabular-nums font-semibold text-n-slate-12">
                  {{ (funnel.stages || []).length }}
                </span>
              </span>
              <span class="inline-flex items-center gap-1.5">
                <span
                  class="i-lucide-square-check-big size-3.5 text-n-slate-10"
                />
                <span class="tabular-nums font-semibold text-n-slate-12">
                  {{ totalTasks(funnel) }}
                </span>
              </span>
              <span
                v-if="wonRate(funnel) > 0"
                class="inline-flex items-center gap-1.5 px-1.5 py-0.5 rounded-md bg-n-teal-3 text-n-teal-11 ring-1 ring-inset ring-n-teal-6"
              >
                <span class="i-lucide-trending-up size-3" />
                <span class="tabular-nums font-bold text-[10px]">
                  {{ wonRate(funnel) }}%
                </span>
              </span>
            </div>
            <span
              class="i-lucide-arrow-right size-4 text-n-iris-11 opacity-0 -translate-x-1 group-hover:opacity-100 group-hover:translate-x-0 transition-all"
            />
          </div>
        </button>
      </div>

      <!-- Filtered-empty state -->
      <div
        v-if="!filteredFunnels.length && search"
        class="flex flex-col items-center justify-center gap-2 py-16 text-center"
      >
        <span class="i-lucide-search-x size-8 text-n-slate-10" />
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.OVERVIEW.NO_MATCH', { q: search }) }}
        </p>
      </div>
    </section>

    <woot-modal v-model:show="showFunnelModal" :on-close="closeModal">
      <FunnelFormModal
        :funnel="editingFunnel"
        @submit="handleSubmit"
        @close="closeModal"
      />
    </woot-modal>
  </div>
</template>
