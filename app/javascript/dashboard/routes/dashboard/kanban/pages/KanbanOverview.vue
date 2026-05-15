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
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto">
    <header
      class="flex items-center justify-between flex-shrink-0 px-8 py-6 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('KANBAN.OVERVIEW.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
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
      class="flex-1 flex flex-col items-center justify-center gap-4 px-8 text-center"
    >
      <div
        class="size-16 rounded-2xl bg-n-alpha-1 flex items-center justify-center"
      >
        <span class="i-lucide-kanban-square size-8 text-n-slate-10" />
      </div>
      <div class="flex flex-col gap-1 max-w-md">
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('KANBAN.OVERVIEW.EMPTY_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
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

    <section v-else class="px-8 py-6">
      <div
        class="grid gap-4 [grid-template-columns:repeat(auto-fill,minmax(280px,1fr))]"
      >
        <button
          v-for="funnel in funnels"
          :key="funnel.id"
          type="button"
          class="group flex flex-col gap-3 p-5 rounded-xl bg-n-solid-1 border border-n-weak text-left transition-all hover:border-n-brand hover:-translate-y-0.5 hover:shadow-lg"
          @click="goToBoard(funnel)"
        >
          <div class="flex items-start justify-between gap-2">
            <h3
              class="text-base font-medium text-n-slate-12 line-clamp-2 leading-snug"
            >
              {{ funnel.name }}
            </h3>
            <span
              v-if="isAdmin"
              class="size-7 rounded-md grid place-content-center text-n-slate-10 opacity-0 group-hover:opacity-100 hover:bg-n-alpha-2 transition-all"
              @click="goToSettings(funnel, $event)"
            >
              <span class="i-lucide-settings-2 size-4" />
            </span>
          </div>
          <p
            v-if="funnel.description"
            class="text-sm text-n-slate-11 line-clamp-2"
          >
            {{ funnel.description }}
          </p>
          <div class="flex items-center gap-4 mt-auto pt-2">
            <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
              <span class="i-lucide-layers size-3.5" />
              <span>
                {{
                  t('KANBAN.OVERVIEW.STAGE_COUNT', {
                    n: (funnel.stages || []).length,
                  })
                }}
              </span>
            </div>
            <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
              <span class="i-lucide-square-check-big size-3.5" />
              <span>
                {{ t('KANBAN.OVERVIEW.TASK_COUNT', { n: totalTasks(funnel) }) }}
              </span>
            </div>
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
