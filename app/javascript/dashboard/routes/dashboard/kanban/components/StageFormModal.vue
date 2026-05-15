<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const COLOR_SWATCHES = [
  '#64748B',
  '#0EA5E9',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#EC4899',
  '#14B8A6',
];

const STATUS_TYPES = ['active', 'won', 'lost'];

const props = defineProps({
  stage: { type: Object, default: null },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const form = reactive({
  name: '',
  description: '',
  color: COLOR_SWATCHES[0],
  status_type: 'active',
});

watch(
  () => props.stage,
  next => {
    form.name = next?.name || '';
    form.description = next?.description || '';
    form.color = next?.color || COLOR_SWATCHES[0];
    form.status_type = next?.status_type || 'active';
  },
  { immediate: true }
);

const isEdit = computed(() => Boolean(props.stage));
const titleKey = computed(() =>
  isEdit.value ? 'KANBAN.STAGE.EDIT_TITLE' : 'KANBAN.STAGE.NEW_TITLE'
);
const isValid = computed(() => form.name.trim().length > 0);

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    name: form.name.trim(),
    description: form.description.trim(),
    color: form.color,
    status_type: form.status_type,
  });
};
</script>

<template>
  <div class="flex flex-col max-h-[80vh]">
    <woot-modal-header
      :header-title="t(titleKey)"
      :header-content="t('KANBAN.STAGE.DESCRIPTION')"
    />
    <form
      class="flex flex-col gap-5 px-6 py-5 overflow-y-auto"
      @submit.prevent="onSubmit"
    >
      <Input
        v-model="form.name"
        :label="t('KANBAN.STAGE.FORM.NAME_LABEL')"
        :placeholder="t('KANBAN.STAGE.FORM.NAME_PLACEHOLDER')"
        autofocus
      />
      <div class="flex flex-col gap-1.5">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.STAGE.FORM.DESCRIPTION_LABEL') }}
        </label>
        <textarea
          v-model="form.description"
          rows="2"
          class="px-3 py-2 rounded-md border border-n-weak bg-n-background text-sm text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
        />
      </div>

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.STAGE.FORM.COLOR_LABEL') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="swatch in COLOR_SWATCHES"
            :key="swatch"
            type="button"
            class="size-7 rounded-full border-2 transition-transform hover:scale-110"
            :style="{ backgroundColor: swatch }"
            :class="
              form.color === swatch
                ? 'border-n-slate-12 ring-2 ring-n-brand/40'
                : 'border-transparent'
            "
            @click="form.color = swatch"
          />
        </div>
        <Input v-model="form.color" class="w-32" />
      </div>

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.STAGE.FORM.STATUS_LABEL') }}
        </span>
        <div class="flex gap-2">
          <button
            v-for="status in STATUS_TYPES"
            :key="status"
            type="button"
            class="px-3 py-1.5 rounded-md text-sm border transition-colors"
            :class="
              form.status_type === status
                ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
            "
            @click="form.status_type = status"
          >
            {{ t(`KANBAN.STAGE.STATUS_${status.toUpperCase()}`) }}
          </button>
        </div>
      </div>

      <footer class="flex justify-end gap-2 pt-2">
        <Button
          faded
          slate
          type="button"
          :label="t('KANBAN.STAGE.CANCEL')"
          @click="emit('close')"
        />
        <Button
          type="submit"
          :label="t(isEdit ? 'KANBAN.STAGE.SAVE' : 'KANBAN.STAGE.CREATE')"
          :disabled="!isValid"
        />
      </footer>
    </form>
  </div>
</template>
