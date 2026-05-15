<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
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
const draggingStageId = ref(null);

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

const onStageDragstart = (stage, event) => {
  draggingStageId.value = stage.id;
  if (event?.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    try {
      event.dataTransfer.setData('text/plain', String(stage.id));
    } catch (_) {
      /* noop */
    }
  }
};

const onStageDragend = () => {
  draggingStageId.value = null;
};

const onStageDragover = event => {
  if (draggingStageId.value == null) return;
  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.dataTransfer.dropEffect = 'move';
};

const onStageDrop = async (targetStage, event) => {
  event.preventDefault();
  const sourceId = draggingStageId.value;
  draggingStageId.value = null;
  if (sourceId == null || sourceId === targetStage.id) return;
  const ordered = stages.value.map(s => s.id);
  const fromIdx = ordered.indexOf(sourceId);
  const toIdx = ordered.indexOf(targetStage.id);
  if (fromIdx === -1 || toIdx === -1) return;
  ordered.splice(toIdx, 0, ordered.splice(fromIdx, 1)[0]);
  try {
    await store.dispatch('funnels/reorderStages', {
      funnelId: Number(props.funnelId),
      orderedIds: ordered,
    });
  } catch (error) {
    useAlert(error?.message || t('KANBAN.STAGE.REORDER_ERROR'));
    await store.dispatch('funnels/show', Number(props.funnelId));
  }
};

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
  active: { label: 'KANBAN.STAGE.STATUS_ACTIVE', cls: 'text-n-slate-11 bg-n-alpha-2' },
  won: { label: 'KANBAN.STAGE.STATUS_WON', cls: 'text-n-teal-11 bg-n-teal-2' },
  lost: { label: 'KANBAN.STAGE.STATUS_LOST', cls: 'text-n-ruby-11 bg-n-ruby-2' },
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
      <span class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10" />
    </section>

    <section
      v-else-if="!funnel"
      class="flex-1 flex items-center justify-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD.NOT_FOUND') }}
    </section>

    <section v-else class="flex flex-col gap-6 max-w-3xl px-6 py-6">
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
            <dd class="text-n-slate-12">{{ (funnel.inbox_ids || []).length }}</dd>
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
        <p v-if="!stages.length" class="text-sm text-n-slate-11 py-4 text-center">
          {{ t('KANBAN.SETTINGS.STAGES_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-1.5">
          <li
            v-for="stage in stages"
            :key="stage.id"
            :draggable="true"
            class="flex items-center gap-3 px-3 py-2.5 rounded-lg border border-n-weak bg-n-background hover:border-n-slate-7 transition-colors"
            :class="{ 'opacity-40': draggingStageId === stage.id }"
            @dragstart="onStageDragstart(stage, $event)"
            @dragend="onStageDragend"
            @dragover="onStageDragover"
            @drop="onStageDrop(stage, $event)"
          >
            <span
              class="i-lucide-grip-vertical size-4 text-n-slate-10 cursor-grab"
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
        </ul>
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
