<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';

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
    form.contact_ids = (t2?.contacts || []).map(c => c.id);
    selectedContacts.value = [...(t2?.contacts || [])];
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
    contact_ids: form.contact_ids,
  });
};
</script>

<template>
  <div class="flex flex-col max-h-[88vh] w-full">
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
