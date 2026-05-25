<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  funnel: { type: Object, default: null },
});

const emit = defineEmits(['submit', 'close']);

const AUTOMATION_KEYS = [
  'auto_create_task_for_new_conversation',
  'auto_assign_task_to_agent',
  'sync_task_conversation_assignees',
  'auto_resolve_conversation_on_task_close',
  'auto_win_task_on_conversation_resolve',
  'notify_on_task_stage_change',
  'tag_conversation_with_stage',
];

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const funnelUiFlags = useMapGetter('funnels/getUIFlags');

const form = reactive({
  name: '',
  description: '',
  inbox_ids: [],
  agent_ids: [],
  automation_settings: AUTOMATION_KEYS.reduce(
    (acc, key) => ({ ...acc, [key]: false }),
    {}
  ),
});

const seedForm = source => {
  form.name = source?.name || '';
  form.description = source?.description || '';
  form.inbox_ids = [...(source?.inbox_ids || [])];
  form.agent_ids = [...(source?.agent_ids || [])];
  AUTOMATION_KEYS.forEach(key => {
    form.automation_settings[key] = Boolean(source?.automation_settings?.[key]);
  });
};

watch(
  () => props.funnel,
  next => seedForm(next),
  { immediate: true }
);

const isEdit = computed(() => Boolean(props.funnel));
const titleKey = computed(() =>
  isEdit.value ? 'KANBAN.FUNNEL.EDIT_TITLE' : 'KANBAN.FUNNEL.NEW_TITLE'
);
const submitLabel = computed(() =>
  isEdit.value ? 'KANBAN.FUNNEL.SAVE' : 'KANBAN.FUNNEL.CREATE'
);

const isValid = computed(() => form.name.trim().length > 0);
const isBusy = computed(
  () => funnelUiFlags.value.isCreating || funnelUiFlags.value.isUpdating
);

const toggleInbox = id => {
  const idx = form.inbox_ids.indexOf(id);
  if (idx === -1) form.inbox_ids.push(id);
  else form.inbox_ids.splice(idx, 1);
};

const toggleAgent = id => {
  const idx = form.agent_ids.indexOf(id);
  if (idx === -1) form.agent_ids.push(id);
  else form.agent_ids.splice(idx, 1);
};

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    name: form.name.trim(),
    description: form.description.trim(),
    inbox_ids: form.inbox_ids,
    agent_ids: form.agent_ids,
    automation_settings: { ...form.automation_settings },
  });
};
</script>

<template>
  <div class="flex flex-col max-h-[80vh]">
    <woot-modal-header
      :header-title="t(titleKey)"
      :header-content="t('KANBAN.FUNNEL.DESCRIPTION')"
    />
    <form
      class="flex flex-col gap-5 px-6 py-5 overflow-y-auto"
      @submit.prevent="onSubmit"
    >
      <Input
        v-model="form.name"
        :label="t('KANBAN.FUNNEL.FORM.NAME_LABEL')"
        :placeholder="t('KANBAN.FUNNEL.FORM.NAME_PLACEHOLDER')"
        autofocus
      />
      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.FUNNEL.FORM.DESCRIPTION_LABEL') }}
        </label>
        <textarea
          v-model="form.description"
          rows="3"
          :placeholder="t('KANBAN.FUNNEL.FORM.DESCRIPTION_PLACEHOLDER')"
          class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand resize-none"
        />
      </div>

      <fieldset class="flex flex-col gap-2">
        <legend class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.FUNNEL.FORM.INBOXES_LABEL') }}
        </legend>
        <p v-if="!inboxes.length" class="text-xs text-n-slate-10">
          {{ t('KANBAN.FUNNEL.FORM.NO_INBOXES') }}
        </p>
        <div
          v-else
          class="grid grid-cols-2 gap-1.5 max-h-32 overflow-y-auto pr-1"
        >
          <label
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="flex items-center gap-2 px-2 py-1.5 rounded text-sm text-n-slate-12 hover:bg-n-alpha-1 cursor-pointer"
          >
            <input
              type="checkbox"
              :checked="form.inbox_ids.includes(inbox.id)"
              class="accent-n-brand"
              @change="toggleInbox(inbox.id)"
            />
            <span class="truncate">{{ inbox.name }}</span>
          </label>
        </div>
      </fieldset>

      <fieldset class="flex flex-col gap-2">
        <legend class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.FUNNEL.FORM.AGENTS_LABEL') }}
        </legend>
        <p v-if="!agents.length" class="text-xs text-n-slate-10">
          {{ t('KANBAN.FUNNEL.FORM.NO_AGENTS') }}
        </p>
        <div
          v-else
          class="grid grid-cols-2 gap-1.5 max-h-32 overflow-y-auto pr-1"
        >
          <label
            v-for="agent in agents"
            :key="agent.id"
            class="flex items-center gap-2 px-2 py-1.5 rounded text-sm text-n-slate-12 hover:bg-n-alpha-1 cursor-pointer"
          >
            <input
              type="checkbox"
              :checked="form.agent_ids.includes(agent.id)"
              class="accent-n-brand"
              @change="toggleAgent(agent.id)"
            />
            <span class="truncate">{{ agent.name }}</span>
          </label>
        </div>
      </fieldset>

      <fieldset class="flex flex-col gap-2">
        <legend class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.FUNNEL.FORM.AUTOMATIONS_LABEL') }}
        </legend>
        <label
          v-for="key in AUTOMATION_KEYS"
          :key="key"
          class="flex items-start gap-3 px-3 py-2 rounded-md border border-n-weak hover:border-n-slate-7 cursor-pointer transition-colors"
        >
          <input
            v-model="form.automation_settings[key]"
            type="checkbox"
            class="mt-0.5 accent-n-brand"
          />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm text-n-slate-12">
              {{ t(`KANBAN.FUNNEL.AUTOMATIONS.${key.toUpperCase()}.LABEL`) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t(`KANBAN.FUNNEL.AUTOMATIONS.${key.toUpperCase()}.HINT`) }}
            </span>
          </span>
        </label>
      </fieldset>

      <footer class="flex justify-end gap-2 pt-2">
        <Button
          faded
          slate
          type="button"
          :label="t('KANBAN.FUNNEL.CANCEL')"
          @click="emit('close')"
        />
        <Button
          type="submit"
          :label="t(submitLabel)"
          :disabled="!isValid || isBusy"
          :is-loading="isBusy"
        />
      </footer>
    </form>
  </div>
</template>
