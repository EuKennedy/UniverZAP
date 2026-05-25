<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import FunnelFormModal from '../components/FunnelFormModal.vue';
import StageFormModal from '../components/StageFormModal.vue';

const props = defineProps({
  funnelId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const funnel = computed(() =>
  store.getters['funnels/getFunnel'](Number(props.funnelId))
);
const funnelUiFlags = useMapGetter('funnels/getUIFlags');

const stages = computed(() =>
  (funnel.value?.stages || []).slice().sort((a, b) => a.position - b.position)
);

const showFunnelModal = ref(false);
const showStageModal = ref(false);
const editingStage = ref(null);
const showDeleteFunnelModal = ref(false);
const showDeleteStageModal = ref(false);
const stagePendingDelete = ref(null);

// Tab state — defaults to the General tab so admins land on the most-used
// surface. `automations` is a roadmap placeholder until the stage trigger
// engine lands.
const TABS = ['general', 'stages', 'automations'];
const activeTab = ref('general');
const setTab = key => {
  if (TABS.includes(key)) activeTab.value = key;
};

// Local copy of stages used by vuedraggable. Bound through v-model so
// SortableJS can mutate the order optimistically before the API confirms.
const stagesDraft = ref([]);
const syncStagesDraft = () => {
  stagesDraft.value = stages.value.slice();
};

const onStagesReordered = async () => {
  const orderedIds = stagesDraft.value.map(s => s.id);
  try {
    await store.dispatch('funnels/reorderStages', {
      funnelId: Number(props.funnelId),
      orderedIds,
    });
  } catch (error) {
    useAlert(error?.message || t('KANBAN.STAGE.REORDER_ERROR'));
    await store.dispatch('funnels/show', Number(props.funnelId));
    syncStagesDraft();
  }
};

const ensureFunnel = async () => {
  if (funnel.value) return;
  try {
    await store.dispatch('funnels/show', Number(props.funnelId));
  } catch (error) {
    useAlert(error?.message || t('KANBAN.FUNNEL.LOAD_ERROR'));
  }
};

onMounted(ensureFunnel);

const openEditFunnel = () => {
  showFunnelModal.value = true;
};

const closeFunnelModal = () => {
  showFunnelModal.value = false;
};

const handleFunnelSubmit = async payload => {
  try {
    await store.dispatch('funnels/update', {
      id: Number(props.funnelId),
      ...payload,
    });
    useAlert(t('KANBAN.FUNNEL.UPDATE_SUCCESS'));
    closeFunnelModal();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.FUNNEL.SAVE_ERROR'));
  }
};

const openCreateStage = () => {
  editingStage.value = null;
  showStageModal.value = true;
};

const openEditStage = stage => {
  editingStage.value = stage;
  showStageModal.value = true;
};

const closeStageModal = () => {
  showStageModal.value = false;
  editingStage.value = null;
};

const handleStageSubmit = async payload => {
  try {
    if (editingStage.value) {
      await store.dispatch('funnels/updateStage', {
        funnelId: Number(props.funnelId),
        stageId: editingStage.value.id,
        payload,
      });
      useAlert(t('KANBAN.STAGE.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('funnels/createStage', {
        funnelId: Number(props.funnelId),
        payload,
      });
      useAlert(t('KANBAN.STAGE.CREATE_SUCCESS'));
    }
    closeStageModal();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.STAGE.SAVE_ERROR'));
  }
};

const requestDeleteStage = stage => {
  stagePendingDelete.value = stage;
  showDeleteStageModal.value = true;
};

const cancelDeleteStage = () => {
  stagePendingDelete.value = null;
  showDeleteStageModal.value = false;
};

const confirmDeleteStage = async () => {
  const stage = stagePendingDelete.value;
  if (!stage) return;
  try {
    await store.dispatch('funnels/deleteStage', {
      funnelId: Number(props.funnelId),
      stageId: stage.id,
    });
    useAlert(t('KANBAN.STAGE.DELETE_SUCCESS'));
    cancelDeleteStage();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.STAGE.DELETE_ERROR'));
  }
};

// Keep the local draft in sync whenever the canonical stages change
// (initial load, modal updates, websocket pushes).
watch(stages, syncStagesDraft, { immediate: true });

const openDeleteFunnel = () => {
  showDeleteFunnelModal.value = true;
};

const cancelDeleteFunnel = () => {
  showDeleteFunnelModal.value = false;
};

const confirmDeleteFunnel = async () => {
  try {
    await store.dispatch('funnels/delete', Number(props.funnelId));
    useAlert(t('KANBAN.FUNNEL.DELETE_SUCCESS'));
    router.push(accountScopedRoute('kanban_overview'));
  } catch (error) {
    useAlert(error?.message || t('KANBAN.FUNNEL.DELETE_ERROR'));
  }
};

const goBack = () => {
  router.push(
    accountScopedRoute('kanban_board', { funnelId: Number(props.funnelId) })
  );
};

const STATUS_BADGE = {
  active: {
    label: 'KANBAN.STAGE.STATUS_ACTIVE',
    cls: 'text-n-slate-11 bg-n-alpha-2',
  },
  won: { label: 'KANBAN.STAGE.STATUS_WON', cls: 'text-n-teal-11 bg-n-teal-2' },
  lost: {
    label: 'KANBAN.STAGE.STATUS_LOST',
    cls: 'text-n-ruby-11 bg-n-ruby-2',
  },
};
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto">
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          size="xs"
          ghost
          slate
          :aria-label="t('KANBAN.SETTINGS.BACK')"
          @click="goBack"
        />
        <div class="flex flex-col gap-0.5 min-w-0">
          <h1 class="text-lg font-medium text-n-slate-12 truncate">
            {{ t('KANBAN.SETTINGS.TITLE', { name: funnel?.name || '' }) }}
          </h1>
          <p class="text-xs text-n-slate-11">
            {{ t('KANBAN.SETTINGS.SUBTITLE') }}
          </p>
        </div>
      </div>
    </header>

    <section
      v-if="funnelUiFlags.isFetching && !funnel"
      class="flex-1 flex items-center justify-center"
    >
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <section
      v-else-if="!funnel"
      class="flex-1 flex items-center justify-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD.NOT_FOUND') }}
    </section>

    <nav
      v-else
      class="flex-shrink-0 flex items-center gap-1 px-6 border-b border-n-weak"
      role="tablist"
    >
      <button
        v-for="tab in TABS"
        :key="tab"
        type="button"
        role="tab"
        :aria-selected="activeTab === tab"
        class="relative px-3 py-3 text-xs font-medium tracking-tight transition-colors duration-150 cursor-pointer"
        :class="
          activeTab === tab
            ? 'text-n-slate-12'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="setTab(tab)"
      >
        {{ t(`KANBAN.SETTINGS.TABS.${tab.toUpperCase()}`) }}
        <span
          v-if="activeTab === tab"
          class="absolute inset-x-3 -bottom-px h-0.5 rounded-full bg-n-teal-9"
        />
      </button>
    </nav>

    <section
      v-if="funnel"
      v-show="activeTab === 'general'"
      class="flex flex-col gap-6 max-w-3xl px-6 py-6"
    >
      <article
        class="flex flex-col gap-4 p-5 rounded-xl bg-n-solid-1 border border-n-weak"
      >
        <header class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.SETTINGS.DETAILS_TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-11">
              {{ t('KANBAN.SETTINGS.DETAILS_SUBTITLE') }}
            </p>
          </div>
          <Button
            icon="i-lucide-pen-line"
            size="xs"
            faded
            slate
            :label="t('KANBAN.SETTINGS.EDIT_FUNNEL')"
            @click="openEditFunnel"
          />
        </header>
        <dl class="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs text-n-slate-11 uppercase tracking-wide">
              {{ t('KANBAN.FUNNEL.FORM.NAME_LABEL') }}
            </dt>
            <dd class="text-n-slate-12 truncate">{{ funnel.name }}</dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs text-n-slate-11 uppercase tracking-wide">
              {{ t('KANBAN.SETTINGS.INBOXES_COUNT') }}
            </dt>
            <dd class="text-n-slate-12">
              {{ (funnel.inbox_ids || []).length }}
            </dd>
          </div>
          <div class="flex flex-col gap-0.5 col-span-2">
            <dt class="text-xs text-n-slate-11 uppercase tracking-wide">
              {{ t('KANBAN.FUNNEL.FORM.DESCRIPTION_LABEL') }}
            </dt>
            <dd class="text-n-slate-12 whitespace-pre-line">
              {{ funnel.description || '—' }}
            </dd>
          </div>
        </dl>
      </article>

      <article
        class="flex items-center justify-between p-5 rounded-xl border border-n-ruby-6 bg-n-ruby-2/30"
      >
        <div class="flex flex-col gap-0.5">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.DANGER_TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11">
            {{ t('KANBAN.SETTINGS.DANGER_SUBTITLE') }}
          </p>
        </div>
        <Button
          icon="i-lucide-trash-2"
          size="sm"
          ruby
          :label="t('KANBAN.SETTINGS.DELETE_FUNNEL')"
          @click="openDeleteFunnel"
        />
      </article>
    </section>

    <section
      v-if="funnel"
      v-show="activeTab === 'stages'"
      class="flex flex-col gap-6 max-w-3xl px-6 py-6"
    >
      <article
        class="flex flex-col gap-4 p-5 rounded-xl bg-n-solid-1 border border-n-weak"
      >
        <header class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.SETTINGS.STAGES_TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-11">
              {{ t('KANBAN.SETTINGS.STAGES_SUBTITLE') }}
            </p>
          </div>
          <Button
            icon="i-lucide-plus"
            size="xs"
            :label="t('KANBAN.SETTINGS.NEW_STAGE')"
            @click="openCreateStage"
          />
        </header>
        <p
          v-if="!stagesDraft.length"
          class="text-sm text-n-slate-11 py-4 text-center"
        >
          {{ t('KANBAN.SETTINGS.STAGES_EMPTY') }}
        </p>
        <draggable
          v-else
          v-model="stagesDraft"
          :animation="180"
          handle=".stage-row-handle"
          item-key="id"
          ghost-class="stage-row-ghost"
          class="flex flex-col gap-1.5"
          @end="onStagesReordered"
        >
          <template #item="{ element: stage }">
            <li
              class="flex items-center gap-3 px-3 py-2.5 rounded-lg border border-n-weak bg-n-background hover:border-n-slate-7 transition-colors"
            >
              <span
                class="stage-row-handle i-lucide-grip-vertical size-4 text-n-slate-10 cursor-grab"
              />
              <span
                class="size-2.5 rounded-full flex-shrink-0"
                :style="{ backgroundColor: stage.color }"
              />
              <span class="flex-1 text-sm text-n-slate-12 truncate">
                {{ stage.name }}
              </span>
              <span
                class="px-1.5 py-0.5 rounded text-[10px] uppercase tracking-wide font-medium"
                :class="STATUS_BADGE[stage.status_type]?.cls"
              >
                {{ t(STATUS_BADGE[stage.status_type]?.label) }}
              </span>
              <Button
                icon="i-lucide-pen-line"
                size="xs"
                ghost
                slate
                :aria-label="t('KANBAN.SETTINGS.EDIT_STAGE')"
                @click="openEditStage(stage)"
              />
              <Button
                icon="i-lucide-trash-2"
                size="xs"
                ghost
                ruby
                :aria-label="t('KANBAN.SETTINGS.DELETE_STAGE')"
                @click="requestDeleteStage(stage)"
              />
            </li>
          </template>
        </draggable>
      </article>
    </section>

    <section
      v-if="funnel"
      v-show="activeTab === 'automations'"
      class="flex flex-col gap-6 max-w-3xl px-6 py-6"
    >
      <article
        class="flex flex-col items-center gap-4 p-10 rounded-xl bg-n-solid-1 border border-n-weak text-center"
      >
        <span
          class="inline-flex items-center justify-center size-12 rounded-full bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-workflow" class="size-6" />
        </span>
        <div class="flex flex-col gap-1 max-w-md">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS_TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11 leading-relaxed">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS_SUBTITLE') }}
          </p>
        </div>
        <span
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-n-amber-3 text-n-amber-11 text-[10px] font-bold uppercase tracking-wider"
        >
          {{ t('KANBAN.SETTINGS.COMING_SOON') }}
        </span>
      </article>
    </section>

    <woot-modal v-model:show="showFunnelModal" :on-close="closeFunnelModal">
      <FunnelFormModal
        v-if="showFunnelModal && funnel"
        :funnel="funnel"
        @submit="handleFunnelSubmit"
        @close="closeFunnelModal"
      />
    </woot-modal>

    <woot-modal v-model:show="showStageModal" :on-close="closeStageModal">
      <StageFormModal
        v-if="showStageModal"
        :stage="editingStage"
        @submit="handleStageSubmit"
        @close="closeStageModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteStageModal"
      :on-close="cancelDeleteStage"
      :on-confirm="confirmDeleteStage"
      :title="t('KANBAN.STAGE.DELETE_CONFIRM_TITLE')"
      :message="t('KANBAN.STAGE.DELETE_CONFIRM_MESSAGE')"
      :message-value="stagePendingDelete?.name"
      :confirm-text="t('KANBAN.STAGE.DELETE')"
      :reject-text="t('KANBAN.STAGE.CANCEL')"
    />

    <woot-delete-modal
      v-model:show="showDeleteFunnelModal"
      :on-close="cancelDeleteFunnel"
      :on-confirm="confirmDeleteFunnel"
      :title="t('KANBAN.FUNNEL.DELETE_CONFIRM_TITLE')"
      :message="t('KANBAN.FUNNEL.DELETE_CONFIRM_MESSAGE')"
      :message-value="funnel?.name"
      :confirm-text="t('KANBAN.FUNNEL.DELETE')"
      :reject-text="t('KANBAN.FUNNEL.CANCEL')"
    />
  </div>
</template>

<style>
/* SortableJS ghost while dragging a stage row in the Stages tab. */
.stage-row-ghost {
  opacity: 0.45;
  background: rgba(20, 184, 166, 0.08);
  border-color: rgba(20, 184, 166, 0.45);
}
</style>
