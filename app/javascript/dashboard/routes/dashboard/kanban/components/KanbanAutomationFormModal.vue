<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  automation: { type: Object, default: null },
  funnel: { type: Object, required: true },
});

const emit = defineEmits(['submit', 'close']);

// ---------------------------------------------------------------------------
// Authoritative event + action catalogues. Kept in sync with `KanbanAutomation`
// model constants on the server. Adding a new event/action here without the
// backend counterpart will be rejected by the validator (we lean on the model
// to surface that as a 422 with the offending key).
// ---------------------------------------------------------------------------

const EVENTS = [
  { value: 'task_created', icon: 'i-lucide-circle-plus', hasStage: true },
  {
    value: 'task_moved_to_stage',
    icon: 'i-lucide-arrow-right-circle',
    hasStage: true,
  },
  { value: 'task_moved_to_funnel', icon: 'i-lucide-shuffle', hasStage: false },
  { value: 'task_assigned', icon: 'i-lucide-user-plus', hasStage: false },
  { value: 'task_priority_changed', icon: 'i-lucide-flag', hasStage: false },
  { value: 'task_completed', icon: 'i-lucide-check-check', hasStage: true },
  { value: 'task_overdue', icon: 'i-lucide-alarm-clock', hasStage: false },
  {
    value: 'conversation_attached',
    icon: 'i-lucide-message-square',
    hasStage: false,
  },
];

const ACTION_TYPES = [
  { value: 'assign_user', icon: 'i-lucide-user-plus' },
  { value: 'unassign_users', icon: 'i-lucide-user-x' },
  { value: 'move_to_stage', icon: 'i-lucide-arrow-right-circle' },
  { value: 'set_priority', icon: 'i-lucide-flag' },
  { value: 'set_due_date', icon: 'i-lucide-calendar-clock' },
  { value: 'add_label', icon: 'i-lucide-tag' },
  { value: 'remove_label', icon: 'i-lucide-tag' },
  { value: 'add_subtask', icon: 'i-lucide-list-plus' },
  { value: 'send_message', icon: 'i-lucide-send' },
  { value: 'webhook', icon: 'i-lucide-webhook' },
  { value: 'resolve_conversation', icon: 'i-lucide-check-circle' },
];

const PRIORITIES = ['none', 'low', 'medium', 'high', 'urgent'];

const { t } = useI18n();

const agents = useMapGetter('agents/getAgents');

const stages = computed(() =>
  (props.funnel?.stages || []).slice().sort((a, b) => a.position - b.position)
);

// ---------------------------------------------------------------------------
// Local form state. We expand the model's loose `conditions` JSONB into a
// handful of typed inputs so the form is teachable instead of overwhelming
// new operators. On submit we collapse back into the JSONB shape.
// ---------------------------------------------------------------------------
const form = reactive({
  name: '',
  description: '',
  event_name: EVENTS[0].value,
  active: true,
  conditions: {
    stage_id: null,
    min_priority: null,
    assignee_id_in: [],
  },
  actions: [],
});

// Stable per-action UID so Vue `v-for` keys survive reordering. Using
// `${type}-${idx}` made the reorder buttons swap component identities
// instead of DOM positions, dropping local input state mid-edit.
// `_uid` is local-only — stripped on submit so it never reaches the wire.
let actionUidSeq = 0;
const nextActionUid = () => {
  actionUidSeq += 1;
  return `act-${Date.now().toString(36)}-${actionUidSeq}`;
};

const seedForm = source => {
  form.name = source?.name || '';
  form.description = source?.description || '';
  form.event_name = source?.event_name || EVENTS[0].value;
  form.active = source?.active ?? true;
  const c = source?.conditions || {};
  form.conditions.stage_id = c.stage_id ?? null;
  form.conditions.min_priority = c.min_priority ?? null;
  form.conditions.assignee_id_in = Array.isArray(c.assignee_id_in)
    ? [...c.assignee_id_in]
    : [];
  form.actions = Array.isArray(source?.actions)
    ? source.actions.map(a => ({
        _uid: nextActionUid(),
        type: a.type || a[':type'],
        params: { ...(a.params || {}) },
      }))
    : [];
};

watch(
  () => props.automation,
  next => seedForm(next),
  { immediate: true }
);

const isEdit = computed(() => Boolean(props.automation));
const currentEvent = computed(
  () => EVENTS.find(e => e.value === form.event_name) || EVENTS[0]
);

const actionIsValid = action => {
  const p = action.params || {};
  switch (action.type) {
    case 'assign_user':
      return Boolean(p.user_id);
    case 'move_to_stage':
      return Boolean(p.stage_id);
    case 'set_priority':
      return PRIORITIES.includes(p.priority);
    case 'set_due_date':
      return Number.isFinite(Number(p.in_days)) && Number(p.in_days) >= 0;
    case 'add_label':
    case 'remove_label':
      return Boolean((p.label || '').trim());
    case 'add_subtask':
      return Boolean((p.title || '').trim());
    case 'send_message':
      return Boolean((p.content || '').trim());
    case 'webhook':
      return /^https?:\/\//i.test((p.url || '').trim());
    case 'unassign_users':
    case 'resolve_conversation':
      return true;
    default:
      return false;
  }
};

const isValid = computed(() => {
  if (form.name.trim().length === 0) return false;
  if (form.actions.length === 0) return false;
  // Each action must have its required param filled out — anything that
  // takes a free-form string must be non-empty; ids must be numeric.
  return form.actions.every(actionIsValid);
});

const defaultParamsFor = type => {
  switch (type) {
    case 'set_priority':
      return { priority: 'medium' };
    case 'set_due_date':
      return { in_days: 1 };
    default:
      return {};
  }
};

const addAction = type => {
  form.actions.push({
    _uid: nextActionUid(),
    type,
    params: defaultParamsFor(type),
  });
};
const removeAction = idx => {
  form.actions.splice(idx, 1);
};
const moveAction = (idx, delta) => {
  const target = idx + delta;
  if (target < 0 || target >= form.actions.length) return;
  const [moved] = form.actions.splice(idx, 1);
  form.actions.splice(target, 0, moved);
};

// Conditions shape is event-driven. We only persist keys the user actually
// touched so the model validator sees the minimal hash and we can
// extend the catalogue later without a migration.
const buildConditionsPayload = () => {
  const out = {};
  if (currentEvent.value.hasStage && form.conditions.stage_id) {
    out.stage_id = Number(form.conditions.stage_id);
  }
  if (form.conditions.min_priority)
    out.min_priority = form.conditions.min_priority;
  if (form.conditions.assignee_id_in.length > 0) {
    out.assignee_id_in = form.conditions.assignee_id_in.map(Number);
  }
  return out;
};

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    name: form.name.trim(),
    description: form.description.trim() || null,
    event_name: form.event_name,
    funnel_id: props.funnel.id,
    active: form.active,
    conditions: buildConditionsPayload(),
    // Strip the local-only `_uid` before the payload crosses the wire.
    actions: form.actions.map(a => ({ type: a.type, params: a.params || {} })),
  });
};

const eventLabel = ev =>
  t(`KANBAN.AUTOMATIONS.EVENTS.${ev.value.toUpperCase()}.LABEL`);
const eventDesc = ev =>
  t(`KANBAN.AUTOMATIONS.EVENTS.${ev.value.toUpperCase()}.DESC`);
const actionLabel = a =>
  t(`KANBAN.AUTOMATIONS.ACTIONS.${a.value.toUpperCase()}.LABEL`);
const actionDesc = a =>
  t(`KANBAN.AUTOMATIONS.ACTIONS.${a.value.toUpperCase()}.DESC`);
</script>

<template>
  <div class="flex flex-col max-h-[85vh] w-[640px] max-w-full">
    <woot-modal-header
      :header-title="
        isEdit
          ? t('KANBAN.AUTOMATIONS.EDIT_TITLE')
          : t('KANBAN.AUTOMATIONS.NEW_TITLE')
      "
      :header-content="t('KANBAN.AUTOMATIONS.MODAL_SUBTITLE')"
    />
    <form
      class="flex flex-col gap-5 px-6 py-5 overflow-y-auto"
      @submit.prevent="onSubmit"
    >
      <!-- Active toggle. Inline at top so admins can pause a rule without
           opening every section below. -->
      <label
        class="flex items-center gap-3 p-3 rounded-lg border border-n-weak bg-n-solid-1"
      >
        <input
          v-model="form.active"
          type="checkbox"
          class="size-4 rounded border-n-weak"
        />
        <div class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.AUTOMATIONS.FORM.ACTIVE_LABEL') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('KANBAN.AUTOMATIONS.FORM.ACTIVE_HINT') }}
          </span>
        </div>
      </label>

      <Input
        v-model="form.name"
        :label="t('KANBAN.AUTOMATIONS.FORM.NAME_LABEL')"
        :placeholder="t('KANBAN.AUTOMATIONS.FORM.NAME_PLACEHOLDER')"
        autofocus
      />

      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.AUTOMATIONS.FORM.DESCRIPTION_LABEL') }}
        </span>
        <textarea
          v-model="form.description"
          rows="2"
          :placeholder="t('KANBAN.AUTOMATIONS.FORM.DESCRIPTION_PLACEHOLDER')"
          class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12 resize-none"
        />
      </div>

      <!-- Event trigger picker. Visual cards so the operator picks intent
           (what HAPPENS), not jargon (what the JSON key is). -->
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.AUTOMATIONS.FORM.EVENT_LABEL') }}
        </span>
        <p class="text-xs text-n-slate-11 -mt-1">
          {{ t('KANBAN.AUTOMATIONS.FORM.EVENT_HINT') }}
        </p>
        <div class="grid grid-cols-2 gap-2">
          <button
            v-for="event in EVENTS"
            :key="event.value"
            type="button"
            class="flex items-start gap-2.5 px-3 py-2.5 rounded-lg border text-start transition-colors cursor-pointer"
            :class="
              form.event_name === event.value
                ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
            "
            @click="form.event_name = event.value"
          >
            <Icon :icon="event.icon" class="size-4 mt-0.5 shrink-0" />
            <div class="flex flex-col gap-0.5 min-w-0">
              <span
                class="text-[12.5px] font-medium text-n-slate-12 leading-tight"
              >
                {{ eventLabel(event) }}
              </span>
              <span class="text-[11px] text-n-slate-11 leading-snug">
                {{ eventDesc(event) }}
              </span>
            </div>
          </button>
        </div>
      </div>

      <!-- Conditions section. Only stage_id is event-conditional; the
           other filters are always available so power users can scope
           any rule to a subset of tasks. -->
      <details
        class="rounded-lg border border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <summary
          class="flex items-center justify-between gap-3 px-4 py-3 cursor-pointer select-none text-sm font-medium text-n-slate-12"
        >
          <span class="inline-flex items-center gap-2">
            <Icon icon="i-lucide-filter" class="size-4 text-n-slate-11" />
            {{ t('KANBAN.AUTOMATIONS.FORM.CONDITIONS_LABEL') }}
          </span>
          <Icon icon="i-lucide-chevron-down" class="size-4 text-n-slate-11" />
        </summary>
        <div class="flex flex-col gap-3 px-4 py-3 border-t border-n-weak">
          <p class="text-xs text-n-slate-11">
            {{ t('KANBAN.AUTOMATIONS.FORM.CONDITIONS_HINT') }}
          </p>
          <div v-if="currentEvent.hasStage" class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('KANBAN.AUTOMATIONS.FORM.STAGE_FILTER_LABEL') }}
            </span>
            <select
              v-model="form.conditions.stage_id"
              class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
            >
              <option :value="null">
                {{ t('KANBAN.AUTOMATIONS.FORM.STAGE_FILTER_ANY') }}
              </option>
              <option v-for="stage in stages" :key="stage.id" :value="stage.id">
                {{ stage.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('KANBAN.AUTOMATIONS.FORM.MIN_PRIORITY_LABEL') }}
            </span>
            <select
              v-model="form.conditions.min_priority"
              class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
            >
              <option :value="null">
                {{ t('KANBAN.AUTOMATIONS.FORM.STAGE_FILTER_ANY') }}
              </option>
              <option v-for="p in PRIORITIES" :key="p" :value="p">
                {{ t(`KANBAN.AUTOMATIONS.PRIORITIES.${p.toUpperCase()}`) }}
              </option>
            </select>
          </div>
        </div>
      </details>

      <!-- Action chain. Vertical list with reorder + remove. Inline params
           form per action type. Empty state nudges the operator to add
           the first action so the rule actually does something. -->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <div class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.AUTOMATIONS.FORM.ACTIONS_LABEL') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('KANBAN.AUTOMATIONS.FORM.ACTIONS_HINT') }}
            </span>
          </div>
        </div>

        <ol
          v-if="form.actions.length > 0"
          class="flex flex-col gap-2 list-none m-0 p-0"
        >
          <li
            v-for="(action, idx) in form.actions"
            :key="action._uid"
            class="flex flex-col gap-2 p-3 rounded-lg border border-n-weak bg-n-solid-1"
          >
            <header class="flex items-center gap-2">
              <span
                class="inline-flex items-center justify-center size-6 rounded-md bg-n-teal-3 text-n-teal-11 text-[10px] font-bold"
              >
                {{ idx + 1 }}
              </span>
              <Icon
                :icon="
                  ACTION_TYPES.find(a => a.value === action.type)?.icon ||
                  'i-lucide-zap'
                "
                class="size-4 text-n-slate-11"
              />
              <span class="text-sm text-n-slate-12 flex-1">
                {{ actionLabel({ value: action.type }) }}
              </span>
              <button
                type="button"
                class="text-n-slate-10 hover:text-n-slate-12 size-6 inline-flex items-center justify-center rounded transition-colors"
                :disabled="idx === 0"
                :class="{ 'opacity-30 cursor-not-allowed': idx === 0 }"
                @click="moveAction(idx, -1)"
              >
                <span class="i-lucide-arrow-up size-3.5" />
              </button>
              <button
                type="button"
                class="text-n-slate-10 hover:text-n-slate-12 size-6 inline-flex items-center justify-center rounded transition-colors"
                :disabled="idx === form.actions.length - 1"
                :class="{
                  'opacity-30 cursor-not-allowed':
                    idx === form.actions.length - 1,
                }"
                @click="moveAction(idx, 1)"
              >
                <span class="i-lucide-arrow-down size-3.5" />
              </button>
              <button
                type="button"
                class="text-n-slate-10 hover:text-n-ruby-11 size-6 inline-flex items-center justify-center rounded transition-colors"
                @click="removeAction(idx)"
              >
                <span class="i-lucide-trash-2 size-3.5" />
              </button>
            </header>

            <!-- Inline param forms keyed by action type. The model only
                 sees `type` + `params` so any extra keys here are
                 silently dropped — we keep the params shape predictable. -->
            <div
              v-if="action.type === 'assign_user'"
              class="flex flex-col gap-1"
            >
              <select
                v-model="action.params.user_id"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              >
                <option :value="undefined">
                  {{ t('KANBAN.AUTOMATIONS.FORM.AGENT_PLACEHOLDER') }}
                </option>
                <option
                  v-for="agent in agents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name }}
                </option>
              </select>
            </div>
            <div
              v-else-if="action.type === 'move_to_stage'"
              class="flex flex-col gap-1"
            >
              <select
                v-model="action.params.stage_id"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              >
                <option :value="undefined">
                  {{ t('KANBAN.AUTOMATIONS.FORM.STAGE_PLACEHOLDER') }}
                </option>
                <option
                  v-for="stage in stages"
                  :key="stage.id"
                  :value="stage.id"
                >
                  {{ stage.name }}
                </option>
              </select>
            </div>
            <div
              v-else-if="action.type === 'set_priority'"
              class="flex flex-col gap-1"
            >
              <select
                v-model="action.params.priority"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              >
                <option v-for="p in PRIORITIES" :key="p" :value="p">
                  {{ t(`KANBAN.AUTOMATIONS.PRIORITIES.${p.toUpperCase()}`) }}
                </option>
              </select>
            </div>
            <div
              v-else-if="action.type === 'set_due_date'"
              class="flex items-center gap-2"
            >
              <input
                v-model.number="action.params.in_days"
                type="number"
                min="0"
                class="flex-1 px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              />
              <span class="text-xs text-n-slate-11">
                {{ t('KANBAN.AUTOMATIONS.FORM.DAYS_SUFFIX') }}
              </span>
            </div>
            <div
              v-else-if="['add_label', 'remove_label'].includes(action.type)"
              class="flex flex-col gap-1"
            >
              <input
                v-model="action.params.label"
                type="text"
                :placeholder="t('KANBAN.AUTOMATIONS.FORM.LABEL_PLACEHOLDER')"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              />
            </div>
            <div
              v-else-if="action.type === 'add_subtask'"
              class="flex flex-col gap-1"
            >
              <input
                v-model="action.params.title"
                type="text"
                :placeholder="t('KANBAN.AUTOMATIONS.FORM.SUBTASK_PLACEHOLDER')"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              />
            </div>
            <div
              v-else-if="action.type === 'send_message'"
              class="flex flex-col gap-1"
            >
              <textarea
                v-model="action.params.content"
                rows="3"
                :placeholder="t('KANBAN.AUTOMATIONS.FORM.MESSAGE_PLACEHOLDER')"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12 resize-none"
              />
            </div>
            <div
              v-else-if="action.type === 'webhook'"
              class="flex flex-col gap-1"
            >
              <input
                v-model="action.params.url"
                type="url"
                :placeholder="t('KANBAN.AUTOMATIONS.FORM.WEBHOOK_PLACEHOLDER')"
                class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12"
              />
            </div>
            <p v-else class="text-xs text-n-slate-11">
              {{ actionDesc({ value: action.type }) }}
            </p>
          </li>
        </ol>
        <p v-else class="text-xs text-n-slate-11 text-center py-3">
          {{ t('KANBAN.AUTOMATIONS.FORM.ACTIONS_EMPTY') }}
        </p>

        <details
          class="rounded-lg border border-n-weak bg-n-solid-1 overflow-hidden"
        >
          <summary
            class="flex items-center justify-between gap-3 px-4 py-3 cursor-pointer select-none text-sm font-medium text-n-teal-11"
          >
            <span class="inline-flex items-center gap-2">
              <Icon icon="i-lucide-plus" class="size-4" />
              {{ t('KANBAN.AUTOMATIONS.FORM.ADD_ACTION') }}
            </span>
            <Icon icon="i-lucide-chevron-down" class="size-4" />
          </summary>
          <div
            class="grid grid-cols-2 md:grid-cols-3 gap-2 px-3 py-3 border-t border-n-weak"
          >
            <button
              v-for="a in ACTION_TYPES"
              :key="a.value"
              type="button"
              class="flex items-center gap-2 px-3 py-2.5 rounded-lg border border-n-weak text-start text-n-slate-11 hover:border-n-slate-7 hover:text-n-slate-12 transition-colors cursor-pointer"
              @click="addAction(a.value)"
            >
              <Icon :icon="a.icon" class="size-4 shrink-0" />
              <span class="text-[12px] font-medium leading-tight">
                {{ actionLabel(a) }}
              </span>
            </button>
          </div>
        </details>
      </div>

      <footer class="flex justify-end gap-2 pt-3 border-t border-n-weak">
        <Button
          faded
          slate
          type="button"
          :label="t('KANBAN.AUTOMATIONS.CANCEL')"
          @click="emit('close')"
        />
        <Button
          type="submit"
          teal
          solid
          :label="
            isEdit
              ? t('KANBAN.AUTOMATIONS.SAVE')
              : t('KANBAN.AUTOMATIONS.CREATE')
          "
          :disabled="!isValid"
        />
      </footer>
    </form>
  </div>
</template>
