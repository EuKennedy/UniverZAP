<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TaskAssigneeSelect from './TaskAssigneeSelect.vue';

const props = defineProps({
  selectedIds: {
    type: Array,
    default: () => [],
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'complete',
  'delete',
  'assign',
  'setUrgency',
  'cancel',
]);

const { t } = useI18n();

const URGENCIES = [
  { value: 'urgent', labelKey: 'TASKS.URGENCY.URGENT' },
  { value: 'high', labelKey: 'TASKS.URGENCY.HIGH' },
  { value: 'medium', labelKey: 'TASKS.URGENCY.MEDIUM' },
  { value: 'low', labelKey: 'TASKS.URGENCY.LOW' },
  { value: 'none', labelKey: 'TASKS.URGENCY.NONE' },
];

const count = computed(() => props.selectedIds.length);
const showUrgencyMenu = ref(false);
const showAssignPopover = ref(false);
const assigneeIds = ref([]);

const submitAssign = () => {
  if (!assigneeIds.value.length) return;
  emit('assign', assigneeIds.value[0]);
  showAssignPopover.value = false;
  assigneeIds.value = [];
};

const applyUrgency = urgency => {
  showUrgencyMenu.value = false;
  emit('setUrgency', urgency);
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="count > 0"
      class="fixed bottom-4 left-1/2 -translate-x-1/2 z-40 flex items-center gap-2 px-3 py-2 rounded-xl bg-n-solid-1 ring-1 ring-n-weak shadow-2xl backdrop-blur"
      data-test-id="tasks-bulk-action-bar"
    >
      <span
        class="text-[12px] font-medium text-n-slate-12 tabular-nums px-2"
        data-test-id="tasks-bulk-action-count"
      >
        {{ t('TASKS.BULK.SELECTED_COUNT', { n: count }) }}
      </span>

      <span class="w-px h-5 bg-n-weak" />

      <Button
        icon="i-lucide-check"
        :label="t('TASKS.BULK.COMPLETE')"
        size="xs"
        ghost
        teal
        :disabled="isBusy"
        data-test-id="tasks-bulk-complete"
        @click="emit('complete')"
      />

      <Button
        icon="i-lucide-trash-2"
        :label="t('TASKS.BULK.DELETE')"
        size="xs"
        ghost
        ruby
        :disabled="isBusy"
        data-test-id="tasks-bulk-delete"
        @click="emit('delete')"
      />

      <div class="relative">
        <Button
          icon="i-lucide-user-plus"
          :label="t('TASKS.BULK.ASSIGN')"
          size="xs"
          ghost
          slate
          :disabled="isBusy"
          data-test-id="tasks-bulk-assign-toggle"
          @click="showAssignPopover = !showAssignPopover"
        />
        <div
          v-if="showAssignPopover"
          class="absolute bottom-full left-0 mb-2 w-64 p-3 rounded-lg bg-n-solid-1 ring-1 ring-n-weak shadow-xl"
        >
          <TaskAssigneeSelect v-model="assigneeIds" />
          <Button
            :label="t('TASKS.BULK.APPLY')"
            size="xs"
            solid
            blue
            class="mt-2 w-full"
            data-test-id="tasks-bulk-assign-apply"
            @click="submitAssign"
          />
        </div>
      </div>

      <div class="relative">
        <Button
          icon="i-lucide-flag"
          :label="t('TASKS.BULK.URGENCY')"
          size="xs"
          ghost
          amber
          :disabled="isBusy"
          data-test-id="tasks-bulk-urgency-toggle"
          @click="showUrgencyMenu = !showUrgencyMenu"
        />
        <ul
          v-if="showUrgencyMenu"
          class="absolute bottom-full left-0 mb-2 w-40 rounded-lg bg-n-solid-1 ring-1 ring-n-weak shadow-xl overflow-hidden"
        >
          <li v-for="opt in URGENCIES" :key="opt.value">
            <button
              type="button"
              class="w-full text-left px-3 py-1.5 text-[12px] text-n-slate-12 hover:bg-n-alpha-1"
              :data-test-id="`tasks-bulk-urgency-${opt.value}`"
              @click="applyUrgency(opt.value)"
            >
              {{ t(opt.labelKey) }}
            </button>
          </li>
        </ul>
      </div>

      <span class="w-px h-5 bg-n-weak" />

      <Button
        icon="i-lucide-x"
        :label="t('TASKS.BULK.CANCEL')"
        size="xs"
        ghost
        slate
        data-test-id="tasks-bulk-cancel"
        @click="emit('cancel')"
      />
    </div>
  </Teleport>
</template>
