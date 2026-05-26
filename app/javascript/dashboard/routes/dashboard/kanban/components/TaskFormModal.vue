<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import KanbanTasksAPI from 'dashboard/api/kanbanTasks';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

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
  estimate_minutes: null,
  assignee_ids: [],
  label_ids: [],
  contact_ids: [],
});

const selectedContacts = ref([]);
const contactSearch = ref('');
const contactResults = ref([]);
const contactSearchOpen = ref(false);
const contactSearching = ref(false);
let searchTimer = null;

// Subtasks live in their own reactive list. We sync from props.task whenever
// the parent task changes (modal open / outside update) but otherwise own the
// list locally — every mutation re-renders the checklist optimistically and
// reconciles with the API response.
const subtasks = ref([]);
const subtaskDraft = ref('');
const subtaskBusy = ref(null); // 'new' | <subtask_id> | null

const subtasksDoneCount = computed(
  () => subtasks.value.filter(s => s.completed_at).length
);

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
    form.estimate_minutes = t2?.estimate_minutes ?? null;
    form.assignee_ids = (t2?.assignees || []).map(a => a.id);
    form.label_ids = (t2?.labels || []).map(l => l.id);
    form.contact_ids = (t2?.contacts || []).map(c => c.id);
    selectedContacts.value = [...(t2?.contacts || [])];
    subtasks.value = [...(t2?.subtasks || [])];
    subtaskDraft.value = '';
  },
  { immediate: true }
);

const onCreateSubtask = async () => {
  const title = subtaskDraft.value.trim();
  if (!title || !props.task || subtaskBusy.value) return;
  subtaskBusy.value = 'new';
  try {
    const { data } = await KanbanTasksAPI.createSubtask({
      parentTaskId: props.task.id,
      funnelId: props.funnel.id,
      funnelStageId: props.task.funnel_stage_id,
      title,
    });
    const created = data?.data || data;
    if (created?.id) {
      subtasks.value = [
        ...subtasks.value,
        {
          id: created.id,
          title: created.title,
          position: created.position,
          completed_at: created.completed_at,
        },
      ];
    }
    subtaskDraft.value = '';
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.FORM.SUBTASK_ERROR'));
  } finally {
    subtaskBusy.value = null;
  }
};

const onToggleSubtask = async subtask => {
  if (subtaskBusy.value) return;
  subtaskBusy.value = subtask.id;
  const nextCompletedAt = subtask.completed_at
    ? null
    : Math.floor(Date.now() / 1000);
  try {
    await KanbanTasksAPI.toggleSubtask(subtask.id, nextCompletedAt);
    subtasks.value = subtasks.value.map(s =>
      s.id === subtask.id ? { ...s, completed_at: nextCompletedAt } : s
    );
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.FORM.SUBTASK_ERROR'));
  } finally {
    subtaskBusy.value = null;
  }
};

const onDeleteSubtask = async subtask => {
  if (subtaskBusy.value) return;
  subtaskBusy.value = subtask.id;
  try {
    await KanbanTasksAPI.destroySubtask(subtask.id);
    subtasks.value = subtasks.value.filter(s => s.id !== subtask.id);
  } catch (error) {
    useAlert(error?.message || t('KANBAN.TASK.FORM.SUBTASK_ERROR'));
  } finally {
    subtaskBusy.value = null;
  }
};

const isEdit = computed(() => Boolean(props.task));
const stages = computed(() => props.funnel?.stages || []);
const isValid = computed(
  () => form.title.trim().length > 0 && Boolean(form.funnel_stage_id)
);
const isBusy = computed(
  () => taskUiFlags.value.isCreating || taskUiFlags.value.isUpdating
);
const primaryContact = computed(() => selectedContacts.value[0] || null);

const performSearch = async query => {
  if (!query || query.length < 2) {
    contactResults.value = [];
    return;
  }
  contactSearching.value = true;
  try {
    const response = await ContactAPI.search(query);
    const payload = response?.data?.payload || response?.data || [];
    contactResults.value = payload.slice(0, 8);
  } catch (_error) {
    contactResults.value = [];
  } finally {
    contactSearching.value = false;
  }
};

watch(contactSearch, value => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => performSearch(value), 250);
});

const isContactSelected = id => selectedContacts.value.some(c => c.id === id);

const addContact = contact => {
  if (isContactSelected(contact.id)) return;
  selectedContacts.value.push(contact);
  form.contact_ids = selectedContacts.value.map(c => c.id);
  if (!form.title.trim() && selectedContacts.value.length === 1) {
    form.title = contact.name;
  }
  contactSearch.value = '';
  contactResults.value = [];
};

const removeContact = id => {
  selectedContacts.value = selectedContacts.value.filter(c => c.id !== id);
  form.contact_ids = selectedContacts.value.map(c => c.id);
};

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

// Custom field values keyed by funnel_custom_field_id. We hydrate from the
// task's `custom_values` array (server-side payload) on open and convert back
// into the array shape the API expects on submit.
const customFieldValues = ref({});

const funnelCustomFields = computed(() => props.funnel?.custom_fields || []);

watch(
  () => [props.task, props.funnel],
  () => {
    const map = {};
    (props.task?.custom_values || []).forEach(entry => {
      map[entry.funnel_custom_field_id] = entry.value;
    });
    customFieldValues.value = map;
  },
  { immediate: true }
);

const setCustomFieldValue = (fieldId, value) => {
  customFieldValues.value = { ...customFieldValues.value, [fieldId]: value };
};

const toggleMultiSelectChoice = (fieldId, choice) => {
  const current = customFieldValues.value[fieldId];
  const arr = Array.isArray(current) ? [...current] : [];
  const idx = arr.indexOf(choice);
  if (idx === -1) arr.push(choice);
  else arr.splice(idx, 1);
  setCustomFieldValue(fieldId, arr);
};

const serializeCustomValues = () =>
  funnelCustomFields.value
    .map(field => ({
      funnel_custom_field_id: field.id,
      value: customFieldValues.value[field.id] ?? null,
    }))
    .filter(entry => entry.value !== null && entry.value !== '');

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    title: form.title.trim(),
    description: form.description.trim(),
    priority: form.priority,
    funnel_stage_id: form.funnel_stage_id,
    start_date: inputToTs(form.start_date),
    due_date: inputToTs(form.due_date),
    estimate_minutes:
      form.estimate_minutes && form.estimate_minutes > 0
        ? Number(form.estimate_minutes)
        : null,
    assignee_ids: form.assignee_ids,
    label_ids: form.label_ids,
    contact_ids: form.contact_ids,
    custom_values: serializeCustomValues(),
  });
};
</script>

<template>
  <div class="flex flex-col h-full w-full">
    <header
      class="flex items-start justify-between gap-4 px-7 py-5 border-b border-n-weak flex-shrink-0"
    >
      <div class="flex flex-col gap-1 min-w-0">
        <span
          class="text-[10px] font-bold uppercase tracking-[0.18em] text-n-teal-11"
        >
          {{
            isEdit ? t('KANBAN.TASK.EDIT_BADGE') : t('KANBAN.TASK.NEW_BADGE')
          }}
        </span>
        <h2
          class="text-xl font-semibold text-n-slate-12 m-0 leading-tight tracking-tight truncate"
        >
          {{
            isEdit ? t('KANBAN.TASK.EDIT_TITLE') : t('KANBAN.TASK.NEW_TITLE')
          }}
        </h2>
        <p class="text-xs text-n-slate-11 m-0 leading-relaxed">
          {{ t('KANBAN.TASK.DESCRIPTION') }}
        </p>
      </div>
      <button
        type="button"
        class="shrink-0 inline-flex items-center justify-center size-9 rounded-lg text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
        :aria-label="t('KANBAN.TASK.CANCEL')"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-5" />
      </button>
    </header>
    <form
      class="flex flex-col gap-5 px-7 py-6 overflow-y-auto flex-1"
      @submit.prevent="onSubmit"
    >
      <section
        class="flex flex-col gap-2 p-4 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <div class="flex items-center justify-between">
          <label
            class="text-[11px] font-semibold text-n-slate-11 uppercase tracking-wider"
          >
            {{ t('KANBAN.TASK.FORM.CONTACTS_LABEL') }}
          </label>
          <span
            v-if="selectedContacts.length"
            class="text-[11px] text-n-slate-10 tabular-nums"
          >
            {{ selectedContacts.length }}
          </span>
        </div>

        <div
          v-if="primaryContact"
          class="flex items-center gap-3 p-2 rounded-lg bg-n-solid-1 ring-1 ring-n-weak"
        >
          <Avatar
            :src="primaryContact.thumbnail || primaryContact.avatar_url"
            :name="primaryContact.name"
            :size="36"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-semibold text-n-slate-12 truncate">
              {{ primaryContact.name }}
            </span>
            <span class="text-[11px] text-n-slate-11 truncate">
              {{
                primaryContact.email ||
                primaryContact.phone_number ||
                t('KANBAN.TASK.FORM.NO_CONTACT_DETAILS')
              }}
            </span>
          </div>
          <button
            type="button"
            class="size-7 rounded-md grid place-content-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-11 transition-colors"
            :aria-label="t('KANBAN.TASK.FORM.REMOVE_CONTACT')"
            @click="removeContact(primaryContact.id)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <div v-if="selectedContacts.length > 1" class="flex flex-wrap gap-1.5">
          <span
            v-for="contact in selectedContacts.slice(1)"
            :key="contact.id"
            class="inline-flex items-center gap-1.5 pl-1 pr-2 py-0.5 rounded-full bg-n-solid-1 ring-1 ring-n-weak text-[12px] text-n-slate-12"
          >
            <Avatar
              :src="contact.thumbnail || contact.avatar_url"
              :name="contact.name"
              :size="18"
              rounded-full
            />
            {{ contact.name }}
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-ruby-11"
              @click="removeContact(contact.id)"
            >
              <span class="i-lucide-x size-3" />
            </button>
          </span>
        </div>

        <div class="relative">
          <div
            class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-solid-1 ring-1 ring-n-weak focus-within:ring-n-brand"
          >
            <span
              class="i-lucide-search size-4 text-n-slate-10 flex-shrink-0"
            />
            <input
              v-model="contactSearch"
              type="text"
              :placeholder="t('KANBAN.TASK.FORM.CONTACT_SEARCH_PLACEHOLDER')"
              class="flex-1 bg-transparent text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
              @focus="contactSearchOpen = true"
              @blur="setTimeout(() => (contactSearchOpen = false), 150)"
            />
            <span
              v-if="contactSearching"
              class="i-lucide-loader-circle size-3.5 animate-spin text-n-slate-10"
            />
          </div>
          <div
            v-if="contactSearchOpen && contactResults.length"
            class="absolute left-0 right-0 top-full mt-1 z-20 max-h-64 overflow-y-auto rounded-lg bg-n-solid-2 ring-1 ring-n-weak shadow-xl py-1"
          >
            <button
              v-for="contact in contactResults"
              :key="contact.id"
              type="button"
              class="w-full flex items-center gap-2.5 px-3 py-2 text-left hover:bg-n-alpha-1 transition-colors"
              :disabled="isContactSelected(contact.id)"
              :class="{
                'opacity-40 cursor-not-allowed': isContactSelected(contact.id),
              }"
              @mousedown.prevent="addContact(contact)"
            >
              <Avatar
                :src="contact.thumbnail"
                :name="contact.name"
                :size="28"
                rounded-full
              />
              <div class="flex flex-col flex-1 min-w-0">
                <span class="text-[13px] font-medium text-n-slate-12 truncate">
                  {{ contact.name }}
                </span>
                <span class="text-[11px] text-n-slate-11 truncate">
                  {{ contact.email || contact.phone_number || '—' }}
                </span>
              </div>
              <span
                v-if="isContactSelected(contact.id)"
                class="i-lucide-check size-4 text-n-teal-11"
              />
            </button>
          </div>
          <div
            v-else-if="
              contactSearchOpen &&
              contactSearch.length >= 2 &&
              !contactSearching
            "
            class="absolute left-0 right-0 top-full mt-1 z-20 px-3 py-2 rounded-lg bg-n-solid-2 ring-1 ring-n-weak text-[12px] text-n-slate-11"
          >
            {{ t('KANBAN.TASK.FORM.CONTACT_NOT_FOUND') }}
          </div>
        </div>
      </section>

      <Input
        v-model="form.title"
        :label="t('KANBAN.TASK.FORM.TITLE_LABEL')"
        :placeholder="t('KANBAN.TASK.FORM.TITLE_PLACEHOLDER')"
        autofocus
      />

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.TASK.FORM.STAGE_LABEL') }}
          </label>
          <select
            v-model="form.funnel_stage_id"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
            :disabled="!stages.length"
          >
            <option v-if="!stages.length" :value="null" disabled selected>
              {{ t('KANBAN.TASK.FORM.STAGE_EMPTY') }}
            </option>
            <option v-for="stage in stages" :key="stage.id" :value="stage.id">
              {{ stage.name }}
            </option>
          </select>
          <p
            v-if="!stages.length"
            class="text-[11px] text-n-amber-11 bg-n-amber-3 px-2 py-1 rounded-md ring-1 ring-inset ring-n-amber-6 leading-snug"
          >
            {{ t('KANBAN.TASK.FORM.STAGE_EMPTY_HINT') }}
          </p>
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

      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.TASK.FORM.DESCRIPTION_LABEL') }}
        </label>
        <textarea
          v-model="form.description"
          rows="3"
          class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
        />
      </div>

      <div class="grid grid-cols-3 gap-3">
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
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.TASK.FORM.ESTIMATE_LABEL') }}
          </label>
          <div
            class="flex items-center gap-1 px-3 py-2 rounded-md border border-n-weak bg-n-background focus-within:border-n-brand"
          >
            <input
              v-model.number="form.estimate_minutes"
              type="number"
              min="0"
              step="15"
              :placeholder="t('KANBAN.TASK.FORM.ESTIMATE_PLACEHOLDER')"
              class="flex-1 bg-transparent text-sm text-n-slate-12 focus:outline-none tabular-nums [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
            />
            <span class="text-xs text-n-slate-10">
              {{ t('KANBAN.TASK.FORM.ESTIMATE_UNIT') }}
            </span>
          </div>
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

      <section
        v-if="funnelCustomFields.length"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <header class="flex items-center justify-between gap-2">
          <label
            class="text-[11px] font-semibold text-n-slate-11 uppercase tracking-wider"
          >
            {{ t('KANBAN.CUSTOM_FIELDS.TITLE') }}
          </label>
        </header>
        <div
          v-for="field in funnelCustomFields"
          :key="field.id"
          class="flex flex-col gap-1.5"
        >
          <label
            class="text-[12px] font-medium text-n-slate-12 flex items-center gap-1"
          >
            {{ field.name }}
            <span
              v-if="field.required"
              class="text-n-ruby-11"
              aria-hidden="true"
            >
              *
            </span>
          </label>
          <input
            v-if="field.field_type === 'text'"
            type="text"
            :value="customFieldValues[field.id] || ''"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
            @input="setCustomFieldValue(field.id, $event.target.value)"
          />
          <input
            v-else-if="field.field_type === 'number'"
            type="number"
            :value="customFieldValues[field.id] || ''"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand tabular-nums"
            @input="setCustomFieldValue(field.id, $event.target.value)"
          />
          <input
            v-else-if="field.field_type === 'date'"
            type="date"
            :value="customFieldValues[field.id] || ''"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
            @input="setCustomFieldValue(field.id, $event.target.value)"
          />
          <select
            v-else-if="field.field_type === 'single_select'"
            :value="customFieldValues[field.id] || ''"
            class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand"
            @change="setCustomFieldValue(field.id, $event.target.value)"
          >
            <option value="">—</option>
            <option
              v-for="choice in field.options?.choices || []"
              :key="choice"
              :value="choice"
            >
              {{ choice }}
            </option>
          </select>
          <div
            v-else-if="field.field_type === 'multi_select'"
            class="flex flex-wrap gap-1.5"
          >
            <button
              v-for="choice in field.options?.choices || []"
              :key="choice"
              type="button"
              class="px-2.5 py-1 rounded-full text-[12px] border transition-colors"
              :class="
                Array.isArray(customFieldValues[field.id]) &&
                customFieldValues[field.id].includes(choice)
                  ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                  : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
              "
              @click="toggleMultiSelectChoice(field.id, choice)"
            >
              {{ choice }}
            </button>
          </div>
        </div>
      </section>

      <section
        v-if="isEdit"
        class="flex flex-col gap-2 p-4 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <header class="flex items-center justify-between gap-2">
          <label
            class="text-[11px] font-semibold text-n-slate-11 uppercase tracking-wider"
          >
            {{ t('KANBAN.TASK.FORM.SUBTASKS_LABEL') }}
          </label>
          <span
            v-if="subtasks.length"
            class="text-[11px] text-n-slate-10 tabular-nums"
          >
            {{ subtasksDoneCount }}/{{ subtasks.length }}
          </span>
        </header>

        <ul v-if="subtasks.length" class="flex flex-col gap-1">
          <li
            v-for="subtask in subtasks"
            :key="subtask.id"
            class="group flex items-center gap-2 px-2.5 py-2 rounded-md bg-n-solid-1 ring-1 ring-n-weak transition-colors hover:ring-n-slate-7"
          >
            <button
              type="button"
              class="size-4 rounded-md ring-1 ring-n-slate-7 inline-flex items-center justify-center transition-all duration-150 cursor-pointer"
              :class="
                subtask.completed_at
                  ? 'bg-n-teal-9 ring-n-teal-9 text-white'
                  : 'hover:ring-n-teal-9 hover:bg-n-teal-3/30'
              "
              :aria-pressed="Boolean(subtask.completed_at)"
              :disabled="subtaskBusy === subtask.id"
              @click="onToggleSubtask(subtask)"
            >
              <span v-if="subtask.completed_at" class="i-lucide-check size-3" />
            </button>
            <span
              class="flex-1 text-[13px] text-n-slate-12 truncate"
              :class="{
                'line-through opacity-50': subtask.completed_at,
              }"
            >
              {{ subtask.title }}
            </span>
            <button
              type="button"
              class="opacity-0 group-hover:opacity-100 size-6 rounded-md grid place-content-center text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2 transition-all duration-150 cursor-pointer"
              :aria-label="t('KANBAN.TASK.FORM.SUBTASK_REMOVE')"
              :disabled="subtaskBusy === subtask.id"
              @click="onDeleteSubtask(subtask)"
            >
              <span class="i-lucide-trash-2 size-3.5" />
            </button>
          </li>
        </ul>

        <div
          class="flex items-center gap-2 px-2.5 py-2 rounded-md bg-n-solid-1 ring-1 ring-n-weak focus-within:ring-n-brand"
        >
          <span
            class="i-lucide-plus size-3.5 text-n-slate-10 flex-shrink-0"
            aria-hidden="true"
          />
          <input
            v-model="subtaskDraft"
            type="text"
            :placeholder="t('KANBAN.TASK.FORM.SUBTASK_PLACEHOLDER')"
            class="flex-1 bg-transparent text-[13px] text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
            :disabled="subtaskBusy === 'new'"
            @keydown.enter.prevent="onCreateSubtask"
          />
          <button
            type="button"
            class="text-[11px] font-semibold text-n-teal-11 hover:text-n-teal-12 disabled:opacity-50 transition-colors cursor-pointer"
            :disabled="!subtaskDraft.trim() || subtaskBusy === 'new'"
            @click="onCreateSubtask"
          >
            {{ t('KANBAN.TASK.FORM.SUBTASK_ADD') }}
          </button>
        </div>
      </section>

      <footer
        class="sticky bottom-0 -mx-7 -mb-6 px-7 py-4 bg-n-surface-1/95 backdrop-blur-md border-t border-n-weak flex items-center justify-between gap-2 z-10"
      >
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
