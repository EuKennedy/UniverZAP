<script setup>
import { ref, computed, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TaskAssigneeSelect from './TaskAssigneeSelect.vue';
import TaskRecurrenceForm from './TaskRecurrenceForm.vue';

defineProps({
  isSubmitting: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'create']);

const { t } = useI18n();

const URGENCY_OPTIONS = [
  {
    value: 'urgent',
    labelKey: 'TASKS.URGENCY.URGENT',
    accent: 'ring-n-ruby-8',
  },
  { value: 'high', labelKey: 'TASKS.URGENCY.HIGH', accent: 'ring-n-amber-8' },
  {
    value: 'medium',
    labelKey: 'TASKS.URGENCY.MEDIUM',
    accent: 'ring-n-amber-6',
  },
  { value: 'low', labelKey: 'TASKS.URGENCY.LOW', accent: 'ring-n-teal-6' },
  { value: 'none', labelKey: 'TASKS.URGENCY.NONE', accent: 'ring-n-strong' },
];

const titleInput = ref(null);
const title = ref('');
const description = ref('');
const assigneeIds = ref([]);
const urgency = ref('medium');
const dueDate = ref('');
const notifyAssignees = ref(true);
const recurrenceRule = ref({});

onMounted(() => {
  nextTick(() => titleInput.value?.focus());
});

const isValid = computed(() => title.value.trim().length > 0);

const submit = () => {
  if (!isValid.value) return;
  emit('create', {
    title: title.value.trim(),
    description: description.value
      ? { type: 'doc', content: description.value }
      : {},
    urgency: urgency.value,
    due_date: dueDate.value || null,
    notify_assignees: notifyAssignees.value,
    assignee_ids: assigneeIds.value,
    recurrence_rule: recurrenceRule.value || {},
  });
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-3 backdrop-blur-sm"
    data-test-id="task-create-modal"
    @click.self="emit('close')"
  >
    <form
      class="w-full max-w-lg rounded-2xl bg-n-solid-1 ring-1 ring-n-weak shadow-2xl overflow-hidden"
      @submit.prevent="submit"
    >
      <header
        class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
      >
        <h2 class="text-[15px] font-semibold text-n-slate-12 tracking-tight">
          {{ t('TASKS.CREATE.TITLE') }}
        </h2>
        <button
          type="button"
          class="size-7 grid place-content-center rounded-md text-n-slate-11 hover:bg-n-alpha-1"
          :aria-label="t('TASKS.DETAIL.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>

      <div class="p-5 flex flex-col gap-4 max-h-[70vh] overflow-y-auto">
        <label class="flex flex-col gap-1.5">
          <span
            class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
          >
            {{ t('TASKS.CREATE.TITLE_LABEL') }}
          </span>
          <input
            ref="titleInput"
            v-model="title"
            type="text"
            :placeholder="t('TASKS.CREATE.TITLE_PLACEHOLDER')"
            class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
            data-test-id="task-create-title"
          />
        </label>

        <label class="flex flex-col gap-1.5">
          <span
            class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
          >
            {{ t('TASKS.CREATE.DESCRIPTION_LABEL') }}
          </span>
          <textarea
            v-model="description"
            rows="3"
            :placeholder="t('TASKS.CREATE.DESCRIPTION_PLACEHOLDER')"
            class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10 resize-none"
          />
        </label>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <span
              class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
            >
              {{ t('TASKS.CREATE.ASSIGNEES_LABEL') }}
            </span>
            <TaskAssigneeSelect v-model="assigneeIds" />
          </div>

          <div class="flex flex-col gap-1.5">
            <span
              class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
            >
              {{ t('TASKS.CREATE.URGENCY_LABEL') }}
            </span>
            <div class="flex flex-wrap gap-1">
              <button
                v-for="option in URGENCY_OPTIONS"
                :key="option.value"
                type="button"
                class="text-[12px] h-8 px-2.5 rounded-md ring-1 ring-inset transition-colors"
                :class="[
                  urgency === option.value
                    ? `bg-n-alpha-2 text-n-slate-12 ${option.accent}`
                    : 'bg-n-alpha-1 text-n-slate-11 ring-n-weak hover:text-n-slate-12',
                ]"
                @click="urgency = option.value"
              >
                {{ t(option.labelKey) }}
              </button>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 items-end">
          <label class="flex flex-col gap-1.5">
            <span
              class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
            >
              {{ t('TASKS.CREATE.DUE_DATE_LABEL') }}
            </span>
            <input
              v-model="dueDate"
              type="datetime-local"
              class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12"
            />
          </label>
          <label
            class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak cursor-pointer"
          >
            <input
              v-model="notifyAssignees"
              type="checkbox"
              class="size-4 accent-n-brand"
            />
            <span class="text-sm text-n-slate-12">
              {{ t('TASKS.CREATE.NOTIFY_LABEL') }}
            </span>
          </label>
        </div>

        <TaskRecurrenceForm v-model="recurrenceRule" />
      </div>

      <footer
        class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak bg-n-alpha-1/40"
      >
        <Button
          type="button"
          :label="t('TASKS.CREATE.CANCEL')"
          size="sm"
          ghost
          slate
          @click="emit('close')"
        />
        <Button
          type="submit"
          :label="t('TASKS.CREATE.SUBMIT')"
          size="sm"
          solid
          blue
          :is-loading="isSubmitting"
          :disabled="!isValid || isSubmitting"
          data-test-id="task-create-submit"
        />
      </footer>
    </form>
  </div>
</template>
