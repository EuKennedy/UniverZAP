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

const stagePreview = funnel => (funnel.stages || []).slice(0, 6);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-background">
    <header
      class="flex items-center justify-between flex-shrink-0 px-10 py-8 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1.5">
        <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">
          {{ t('KANBAN.OVERVIEW.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 max-w-2xl leading-relaxed">
          {{ t('KANBAN.OVERVIEW.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="isAdmin"
        icon="i-lucide-plus"
        :label="t('KANBAN.OVERVIEW.NEW_FUNNEL')"
        size="sm"
        @click="openCreate"
      />
    </header>

    <section
      v-if="uiFlags.isFetching"
      class="flex-1 flex items-center justify-center"
    >
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <section
      v-else-if="!funnels.length"
      class="flex-1 flex flex-col items-center justify-center gap-5 px-8 text-center"
    >
      <div
        class="size-20 rounded-3xl bg-gradient-to-br from-n-brand/20 to-n-brand/[0.04] ring-1 ring-n-weak flex items-center justify-center"
      >
        <span class="i-lucide-kanban-square size-9 text-n-brand" />
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
        @click="openCreate"
      />
    </section>

    <section v-else class="px-10 py-8">
      <div
        class="grid gap-5 [grid-template-columns:repeat(auto-fill,minmax(320px,1fr))]"
      >
        <button
          v-for="funnel in funnels"
          :key="funnel.id"
          type="button"
          class="funnel-card group relative flex flex-col gap-4 p-5 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak text-left overflow-hidden transition-[transform,box-shadow,ring-color] duration-200 ease-out hover:ring-n-slate-7 hover:-translate-y-0.5 hover:shadow-[0_10px_30px_-10px_rgba(0,0,0,0.25)]"
          @click="goToBoard(funnel)"
        >
          <span
            class="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-n-slate-7 to-transparent opacity-0 group-hover:opacity-100 transition-opacity"
          />

          <div class="flex items-start justify-between gap-3">
            <div class="flex flex-col gap-1 min-w-0 flex-1">
              <h3
                class="text-base font-semibold text-n-slate-12 line-clamp-2 leading-snug tracking-tight"
              >
                {{ funnel.name }}
              </h3>
              <p
                v-if="funnel.description"
                class="text-[13px] text-n-slate-11 line-clamp-2 leading-relaxed"
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

          <div
            v-if="stagePreview(funnel).length"
            class="flex items-center gap-1"
          >
            <span
              v-for="stage in stagePreview(funnel)"
              :key="stage.id"
              class="flex-1 h-1 rounded-full opacity-90"
              :style="{ backgroundColor: stage.color }"
              :title="stage.name"
            />
          </div>

          <div
            class="flex items-center justify-between gap-4 mt-auto pt-3 border-t border-n-weak"
          >
            <div class="flex items-center gap-3 text-[12px] text-n-slate-11">
              <span class="inline-flex items-center gap-1.5">
                <span class="i-lucide-layers size-3.5 text-n-slate-10" />
                <span class="tabular-nums font-medium text-n-slate-12">
                  {{ (funnel.stages || []).length }}
                </span>
                <span class="text-n-slate-11">{{
                  t('KANBAN.OVERVIEW.STAGE_COUNT', {
                    n: (funnel.stages || []).length,
                  }).replace(/^\d+\s*/, '')
                }}</span>
              </span>
              <span class="inline-flex items-center gap-1.5">
                <span
                  class="i-lucide-square-check-big size-3.5 text-n-slate-10"
                />
                <span class="tabular-nums font-medium text-n-slate-12">
                  {{ totalTasks(funnel) }}
                </span>
                <span class="text-n-slate-11">{{
                  t('KANBAN.OVERVIEW.TASK_COUNT', {
                    n: totalTasks(funnel),
                  }).replace(/^\d+\s*/, '')
                }}</span>
              </span>
            </div>
            <span
              class="i-lucide-arrow-right size-4 text-n-slate-10 opacity-0 -translate-x-1 group-hover:opacity-100 group-hover:translate-x-0 transition-all"
            />
          </div>
        </button>
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
