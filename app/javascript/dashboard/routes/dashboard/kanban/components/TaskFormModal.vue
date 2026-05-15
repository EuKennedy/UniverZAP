<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  task: { type: Object, default: null },
  funnel: { type: Object, required: true },
  defaultStageId: { type: [Number, null], default: null },
});

const emit = defineEmits(['submit', 'close', 'delete']);

const PRIORITIES = ['none', 'low', 'medium', 'high', 'urgent'];

const PRIORITY_DOT = {
  none: 'bg-n-slate-7',
  low: 'bg-n-slate-8',
  medium: 'bg-n-blue-9',
  high: 'bg-n-amber-9',
  urgent: 'bg-n-ruby-9',
};

const { t } = useI18n();

const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');
const taskUiFlags = useMapGetter('kanbanTasks/getUIFlags');

const dateToInput = ts => {
  if (!ts) return '';
  return new Date(ts * 1000).toISOString().slice(0, 10);
};

const inputToTs = value => {
  if (!value) return null;
  return Math.floor(new Date(value).getTime() / 1000);
};

const form = reactive({
  title: '',
  description: '',
  priority: 'none',
  funnel_stage_id: null,
  start_date: '',
  due_date: '',
  assignee_ids: [],
  label_ids: [],
});

watch(
  () => [props.task, props.funnel, props.defaultStageId],
  () => {
    const t2 = props.task;
    form.title = t2?.title || '';
    form.description = t2?.description || '';
    form.priority = t2?.priority || 'none';
    form.funnel_stage_id =
      t2?.funnel_stage_id ??
      props.defaultStageId ??
      props.funnel?.stages?.[0]?.id ??
      null;
    form.start_date = dateToInput(t2?.start_date);
    form.due_date = dateToInput(t2?.due_date);
    form.assignee_ids = (t2?.assignees || []).map(a => a.id);
    form.label_ids = (t2?.labels || []).map(l => l.id);
  },
  { immediate: true }
);

const isEdit = computed(() => Boolean(props.task));
const stages = computed(() => props.funnel?.stages || []);
const isValid = computed(
  () => form.title.trim().length > 0 && Boolean(form.funnel_stage_id)
);
const isBusy = computed(
  () => taskUiFlags.value.isCreating || taskUiFlags.value.isUpdating
);

const toggleAssignee = id => {
  const idx = form.assignee_ids.indexOf(id);
  if (idx === -1) form.assignee_ids.push(id);
  else form.assignee_ids.splice(idx, 1);
};

const toggleLabel = id => {
  const idx = form.label_ids.indexOf(id);
  if (idx === -1) form.label_ids.push(id);
  else form.label_ids.splice(idx, 1);
};

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    title: form.title.trim(),
    description: form.description.trim(),
    priority: form.priority,
    funnel_stage_id: form.funnel_stage_id,
    start_date: inputToTs(form.start_date),
    due_date: inputToTs(form.due_date),
    assignee_ids: form.assignee_ids,
    label_ids: form.label_ids,
  });
};
</script>

<template>
  <div class="flex flex-col max-h-[85vh] w-full">
    <woot-modal-header
      :header-title="
        isEdit ? t('KANBAN.TASK.EDIT_TITLE') : t('KANBAN.TASK.NEW_TITLE')
      "
      :header-content="t('KANBAN.TASK.DESCRIPTION')"
    />
    <form
      class="flex flex-col gap-5 px-6 py-5 overflow-y-auto"
      @submit.prevent="onSubmit"
    >
      <Input
        v-model="form.title"
        :label="t('KANBAN.TASK.FORM.TITLE_LABEL')"
        :placeholder="t('KANBAN.TASK.FORM.TITLE_PLACEHOLDER')"
        autofocus
      />

      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.TASK.FORM.DESCRIPTION_LABEL') }}
        </label>
        <textarea
          v-model="form.description"
          rows="4"
          class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
        />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.TASK.FORM.STAGE_LABEL') }}
          </label>
          <select
            v-model="form.funnel_stage_id"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
          >
            <option v-for="stage in stages" :key="stage.id" :value="stage.id">
              {{ stage.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.TASK.FORM.PRIORITY_LABEL') }}
          </label>
          <div class="flex gap-1">
            <button
              v-for="p in PRIORITIES"
              :key="p"
              type="button"
              class="flex-1 px-2 py-1.5 rounded-md text-xs border transition-colors flex items-center justify-center gap-1.5"
              :class="
                form.priority === p
                  ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                  : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
              "
              @click="form.priority = p"
            >
              <span class="size-1.5 rounded-full" :class="PRIORITY_DOT[p]" />
              {{ t(`KANBAN.PRIORITY.${p.toUpperCase()}`) }}
            </button>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.TASK.FORM.START_LABEL') }}
          </label>
          <input
            v-model="form.start_date"
            type="date"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.TASK.FORM.DUE_LABEL') }}
          </label>
          <input
            v-model="form.due_date"
            type="date"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
          />
        </div>
      </div>

      <fieldset class="flex flex-col gap-2">
        <legend class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.TASK.FORM.ASSIGNEES_LABEL') }}
        </legend>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="agent in agents"
            :key="agent.id"
            type="button"
            class="px-2.5 py-1 rounded-full text-xs border transition-colors"
            :class="
              form.assignee_ids.includes(agent.id)
                ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
            "
            @click="toggleAssignee(agent.id)"
          >
            {{ agent.name }}
          </button>
        </div>
      </fieldset>

      <fieldset class="flex flex-col gap-2">
        <legend class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.TASK.FORM.LABELS_LABEL') }}
        </legend>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="label in labels"
            :key="label.id"
            type="button"
            class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs border transition-colors"
            :class="
              form.label_ids.includes(label.id)
                ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
            "
            @click="toggleLabel(label.id)"
          >
            <span
              class="size-1.5 rounded-full"
              :style="{ backgroundColor: label.color }"
            />
            {{ label.title }}
          </button>
        </div>
      </fieldset>

      <footer class="flex items-center justify-between gap-2 pt-2">
        <Button
          v-if="isEdit"
          faded
          ruby
          type="button"
          icon="i-lucide-trash-2"
          :label="t('KANBAN.TASK.DELETE')"
          @click="emit('delete', task)"
        />
        <div v-else />
        <div class="flex gap-2">
          <Button
            faded
            slate
            type="button"
            :label="t('KANBAN.TASK.CANCEL')"
            @click="emit('close')"
          />
          <Button
            type="submit"
            :label="isEdit ? t('KANBAN.TASK.SAVE') : t('KANBAN.TASK.CREATE')"
            :disabled="!isValid || isBusy"
            :is-loading="isBusy"
          />
        </div>
      </footer>
    </form>
  </div>
</template>
