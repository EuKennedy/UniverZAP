<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import draggable from 'vuedraggable';
import FunnelCustomFieldsAPI from 'dashboard/api/funnelCustomFields';
import KanbanAutomationsAPI from 'dashboard/api/kanbanAutomations';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import FunnelFormModal from '../components/FunnelFormModal.vue';
import StageFormModal from '../components/StageFormModal.vue';
import CustomFieldFormModal from '../components/CustomFieldFormModal.vue';
import KanbanAutomationFormModal from '../components/KanbanAutomationFormModal.vue';

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
// surface. The Automations tab drives the per-funnel rule engine
// (`KanbanAutomation` model + Kanban::Automations::Executor on the
// backend).
const TABS = ['general', 'stages', 'custom_fields', 'automations'];
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

// ---------------------------------------------------------------------------
// Custom fields tab — owns its own list/modal lifecycle. The board re-fetches
// the funnel after CRUD so kanban_tasks payload picks the new schema up too.
// ---------------------------------------------------------------------------
const customFields = ref([]);
const showCustomFieldModal = ref(false);
const editingCustomField = ref(null);
const showDeleteCustomFieldModal = ref(false);
const customFieldPendingDelete = ref(null);

const loadCustomFields = async () => {
  try {
    const { data } = await FunnelCustomFieldsAPI.list(props.funnelId);
    customFields.value = data || [];
  } catch (error) {
    useAlert(error?.message || t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR'));
  }
};

const openCreateCustomField = () => {
  editingCustomField.value = null;
  showCustomFieldModal.value = true;
};
const openEditCustomField = field => {
  editingCustomField.value = field;
  showCustomFieldModal.value = true;
};
const closeCustomFieldModal = () => {
  showCustomFieldModal.value = false;
  editingCustomField.value = null;
};

const handleCustomFieldSubmit = async payload => {
  try {
    if (editingCustomField.value) {
      await FunnelCustomFieldsAPI.update(
        props.funnelId,
        editingCustomField.value.id,
        payload
      );
      useAlert(t('KANBAN.CUSTOM_FIELDS.UPDATE_SUCCESS'));
    } else {
      await FunnelCustomFieldsAPI.create(props.funnelId, payload);
      useAlert(t('KANBAN.CUSTOM_FIELDS.CREATE_SUCCESS'));
    }
    closeCustomFieldModal();
    await loadCustomFields();
    await store.dispatch('funnels/show', Number(props.funnelId));
  } catch (error) {
    useAlert(error?.message || t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR'));
  }
};

const requestDeleteCustomField = field => {
  customFieldPendingDelete.value = field;
  showDeleteCustomFieldModal.value = true;
};
const cancelDeleteCustomField = () => {
  customFieldPendingDelete.value = null;
  showDeleteCustomFieldModal.value = false;
};
const confirmDeleteCustomField = async () => {
  const field = customFieldPendingDelete.value;
  if (!field) return;
  try {
    await FunnelCustomFieldsAPI.destroy(props.funnelId, field.id);
    useAlert(t('KANBAN.CUSTOM_FIELDS.DELETE_SUCCESS'));
    cancelDeleteCustomField();
    await loadCustomFields();
    await store.dispatch('funnels/show', Number(props.funnelId));
  } catch (error) {
    useAlert(error?.message || t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR'));
  }
};

watch(
  () => props.funnelId,
  () => loadCustomFields(),
  { immediate: true }
);

const fieldTypeLabel = type =>
  t(`KANBAN.CUSTOM_FIELDS.TYPES.${String(type).toUpperCase()}`);

// ---------------------------------------------------------------------------
// Automations tab — KanbanAutomation CRUD scoped to this funnel. Toggle is
// optimistic (revert + alert on failure). Delete + edit reuse the same
// modal. The backend keeps the funnel_id alongside account-wide rules so
// the filter is mandatory here.
// ---------------------------------------------------------------------------
const automations = ref([]);
const showAutomationModal = ref(false);
const editingAutomation = ref(null);
const showDeleteAutomationModal = ref(false);
const automationPendingDelete = ref(null);
const isAutomationsLoading = ref(false);

const loadAutomations = async () => {
  isAutomationsLoading.value = true;
  try {
    const { data } = await KanbanAutomationsAPI.list({
      funnelId: Number(props.funnelId),
    });
    automations.value = Array.isArray(data) ? data : [];
  } catch (error) {
    useAlert(error?.message || t('KANBAN.AUTOMATIONS.LOAD_ERROR'));
  } finally {
    isAutomationsLoading.value = false;
  }
};

const openCreateAutomation = () => {
  editingAutomation.value = null;
  showAutomationModal.value = true;
};
const openEditAutomation = automation => {
  editingAutomation.value = automation;
  showAutomationModal.value = true;
};
const closeAutomationModal = () => {
  showAutomationModal.value = false;
  editingAutomation.value = null;
};

const handleAutomationSubmit = async payload => {
  try {
    if (editingAutomation.value) {
      await KanbanAutomationsAPI.update(editingAutomation.value.id, payload);
      useAlert(t('KANBAN.AUTOMATIONS.UPDATE_SUCCESS'));
    } else {
      await KanbanAutomationsAPI.create(payload);
      useAlert(t('KANBAN.AUTOMATIONS.CREATE_SUCCESS'));
    }
    closeAutomationModal();
    await loadAutomations();
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join?.(', ') ||
        error?.message ||
        t('KANBAN.AUTOMATIONS.SAVE_ERROR')
    );
  }
};

const requestDeleteAutomation = automation => {
  automationPendingDelete.value = automation;
  showDeleteAutomationModal.value = true;
};
const cancelDeleteAutomation = () => {
  automationPendingDelete.value = null;
  showDeleteAutomationModal.value = false;
};
const confirmDeleteAutomation = async () => {
  const automation = automationPendingDelete.value;
  if (!automation) return;
  try {
    await KanbanAutomationsAPI.destroy(automation.id);
    useAlert(t('KANBAN.AUTOMATIONS.DELETE_SUCCESS'));
    cancelDeleteAutomation();
    await loadAutomations();
  } catch (error) {
    useAlert(error?.message || t('KANBAN.AUTOMATIONS.SAVE_ERROR'));
  }
};

// Optimistic toggle so the switch feels instant. Roll back on failure
// and surface the API error so the operator knows why.
const toggleAutomationActive = async automation => {
  const previous = automation.active;
  const idx = automations.value.findIndex(a => a.id === automation.id);
  if (idx === -1) return;
  automations.value[idx] = { ...automation, active: !previous };
  try {
    await KanbanAutomationsAPI.update(automation.id, { active: !previous });
  } catch (error) {
    automations.value[idx] = { ...automation, active: previous };
    useAlert(error?.message || t('KANBAN.AUTOMATIONS.SAVE_ERROR'));
  }
};

const eventBadgeLabel = eventName =>
  t(`KANBAN.AUTOMATIONS.EVENTS.${String(eventName).toUpperCase()}.LABEL`);

watch(
  () => props.funnelId,
  () => loadAutomations(),
  { immediate: true }
);

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
      v-show="activeTab === 'custom_fields'"
      class="flex flex-col gap-6 max-w-3xl px-6 py-6"
    >
      <article
        class="flex flex-col gap-4 p-5 rounded-xl bg-n-solid-1 border border-n-weak"
      >
        <header class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.CUSTOM_FIELDS.TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-11 leading-relaxed">
              {{ t('KANBAN.CUSTOM_FIELDS.SUBTITLE') }}
            </p>
          </div>
          <Button
            icon="i-lucide-plus"
            size="xs"
            :label="t('KANBAN.CUSTOM_FIELDS.NEW')"
            @click="openCreateCustomField"
          />
        </header>

        <p
          v-if="!customFields.length"
          class="text-sm text-n-slate-11 py-4 text-center"
        >
          {{ t('KANBAN.CUSTOM_FIELDS.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-1.5">
          <li
            v-for="field in customFields"
            :key="field.id"
            class="flex items-center gap-3 px-3 py-2.5 rounded-lg border border-n-weak bg-n-background hover:border-n-slate-7 transition-colors"
          >
            <Icon
              :icon="
                {
                  text: 'i-lucide-text',
                  number: 'i-lucide-hash',
                  date: 'i-lucide-calendar',
                  single_select: 'i-lucide-list',
                  multi_select: 'i-lucide-list-checks',
                }[field.field_type] || 'i-lucide-text'
              "
              class="size-4 text-n-slate-11 flex-shrink-0"
            />
            <span class="flex-1 text-sm text-n-slate-12 truncate">
              {{ field.name }}
            </span>
            <span
              class="px-1.5 py-0.5 rounded text-[10px] uppercase tracking-wide font-medium bg-n-alpha-2 text-n-slate-11"
            >
              {{ fieldTypeLabel(field.field_type) }}
            </span>
            <span
              v-if="field.required"
              class="px-1.5 py-0.5 rounded text-[10px] uppercase tracking-wide font-medium bg-n-ruby-3 text-n-ruby-11"
            >
              {{ t('KANBAN.CUSTOM_FIELDS.REQUIRED') }}
            </span>
            <Button
              icon="i-lucide-pen-line"
              size="xs"
              ghost
              slate
              :aria-label="t('KANBAN.CUSTOM_FIELDS.EDIT')"
              @click="openEditCustomField(field)"
            />
            <Button
              icon="i-lucide-trash-2"
              size="xs"
              ghost
              ruby
              :aria-label="t('KANBAN.CUSTOM_FIELDS.DELETE')"
              @click="requestDeleteCustomField(field)"
            />
          </li>
        </ul>
      </article>
    </section>

    <section
      v-if="funnel"
      v-show="activeTab === 'automations'"
      class="flex flex-col gap-6 max-w-3xl px-6 py-6"
    >
      <article
        class="flex flex-col gap-4 p-5 rounded-xl bg-n-solid-1 border border-n-weak"
      >
        <header class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS_TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-11 leading-relaxed">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS_SUBTITLE') }}
            </p>
          </div>
          <Button
            icon="i-lucide-plus"
            size="xs"
            :label="t('KANBAN.AUTOMATIONS.NEW')"
            @click="openCreateAutomation"
          />
        </header>

        <div
          v-if="isAutomationsLoading"
          class="flex items-center justify-center py-6"
        >
          <span
            class="i-lucide-loader-circle size-5 animate-spin text-n-slate-10"
          />
        </div>
        <div
          v-else-if="!automations.length"
          class="flex flex-col items-center gap-3 py-6 text-center"
        >
          <span
            class="inline-flex items-center justify-center size-10 rounded-full bg-n-teal-3 text-n-teal-11"
          >
            <Icon icon="i-lucide-workflow" class="size-5" />
          </span>
          <p class="text-xs text-n-slate-11 max-w-sm leading-relaxed">
            {{ t('KANBAN.AUTOMATIONS.EMPTY') }}
          </p>
          <Button
            faded
            teal
            size="xs"
            :label="t('KANBAN.AUTOMATIONS.NEW')"
            @click="openCreateAutomation"
          />
        </div>
        <ul v-else class="flex flex-col gap-1.5 list-none m-0 p-0">
          <li
            v-for="automation in automations"
            :key="automation.id"
            class="flex items-center gap-3 px-3 py-3 rounded-lg border border-n-weak bg-n-background hover:border-n-slate-7 transition-colors"
          >
            <span
              class="size-2 rounded-full flex-shrink-0"
              :class="
                automation.active
                  ? 'bg-n-teal-11 shadow-[0_0_0_2px_rgba(16,185,129,0.18)]'
                  : 'bg-n-slate-7'
              "
            />
            <div class="flex flex-col gap-0.5 flex-1 min-w-0">
              <span class="text-sm text-n-slate-12 truncate font-medium">
                {{ automation.name }}
              </span>
              <span class="text-[11px] text-n-slate-11 truncate">
                {{ eventBadgeLabel(automation.event_name) }}
                ·
                {{
                  t('KANBAN.AUTOMATIONS.ACTION_COUNT', {
                    n: (automation.actions || []).length,
                  })
                }}
                <template v-if="automation.last_run_at">
                  ·
                  {{
                    t('KANBAN.AUTOMATIONS.LAST_RUN', {
                      count: automation.run_count || 0,
                    })
                  }}
                </template>
              </span>
            </div>
            <label
              class="inline-flex items-center gap-1.5 cursor-pointer select-none"
              :title="
                automation.active
                  ? t('KANBAN.AUTOMATIONS.PAUSE')
                  : t('KANBAN.AUTOMATIONS.RESUME')
              "
            >
              <input
                type="checkbox"
                :checked="automation.active"
                class="size-4 rounded border-n-weak"
                @change="toggleAutomationActive(automation)"
              />
            </label>
            <Button
              icon="i-lucide-pen-line"
              size="xs"
              ghost
              slate
              :aria-label="t('KANBAN.AUTOMATIONS.EDIT')"
              @click="openEditAutomation(automation)"
            />
            <Button
              icon="i-lucide-trash-2"
              size="xs"
              ghost
              ruby
              :aria-label="t('KANBAN.AUTOMATIONS.DELETE')"
              @click="requestDeleteAutomation(automation)"
            />
          </li>
        </ul>
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

    <woot-modal
      v-model:show="showCustomFieldModal"
      :on-close="closeCustomFieldModal"
    >
      <CustomFieldFormModal
        v-if="showCustomFieldModal"
        :field="editingCustomField"
        @submit="handleCustomFieldSubmit"
        @close="closeCustomFieldModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteCustomFieldModal"
      :on-close="cancelDeleteCustomField"
      :on-confirm="confirmDeleteCustomField"
      :title="t('KANBAN.CUSTOM_FIELDS.DELETE_CONFIRM_TITLE')"
      :message="t('KANBAN.CUSTOM_FIELDS.DELETE_CONFIRM_MESSAGE')"
      :message-value="customFieldPendingDelete?.name"
      :confirm-text="t('KANBAN.CUSTOM_FIELDS.DELETE')"
      :reject-text="t('KANBAN.CUSTOM_FIELDS.CANCEL')"
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

    <woot-modal
      v-model:show="showAutomationModal"
      :on-close="closeAutomationModal"
    >
      <KanbanAutomationFormModal
        v-if="showAutomationModal && funnel"
        :automation="editingAutomation"
        :funnel="funnel"
        @submit="handleAutomationSubmit"
        @close="closeAutomationModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteAutomationModal"
      :on-close="cancelDeleteAutomation"
      :on-confirm="confirmDeleteAutomation"
      :title="t('KANBAN.AUTOMATIONS.DELETE_CONFIRM_TITLE')"
      :message="t('KANBAN.AUTOMATIONS.DELETE_CONFIRM_MESSAGE')"
      :message-value="automationPendingDelete?.name"
      :confirm-text="t('KANBAN.AUTOMATIONS.DELETE')"
      :reject-text="t('KANBAN.AUTOMATIONS.CANCEL')"
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
