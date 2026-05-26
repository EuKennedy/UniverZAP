<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  field: { type: Object, default: null },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const FIELD_TYPES = ['text', 'number', 'date', 'single_select', 'multi_select'];

const form = reactive({
  name: '',
  field_type: 'text',
  required: false,
  options: { choices: [] },
});
const choiceDraft = ref('');

watch(
  () => props.field,
  next => {
    form.name = next?.name || '';
    form.field_type = next?.field_type || 'text';
    form.required = Boolean(next?.required);
    form.options = { choices: [...((next?.options || {}).choices || [])] };
    choiceDraft.value = '';
  },
  { immediate: true }
);

const isSelectType = computed(() =>
  ['single_select', 'multi_select'].includes(form.field_type)
);
const isEdit = computed(() => Boolean(props.field));
const isValid = computed(() => {
  if (form.name.trim().length === 0) return false;
  if (isSelectType.value && !form.options.choices.length) return false;
  return true;
});

const addChoice = () => {
  const value = choiceDraft.value.trim();
  if (!value || form.options.choices.includes(value)) return;
  form.options.choices = [...form.options.choices, value];
  choiceDraft.value = '';
};
const removeChoice = value => {
  form.options.choices = form.options.choices.filter(c => c !== value);
};

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    name: form.name.trim(),
    field_type: form.field_type,
    required: form.required,
    options: isSelectType.value ? { choices: form.options.choices } : {},
  });
};
</script>

<template>
  <div class="flex flex-col max-h-[80vh]">
    <woot-modal-header
      :header-title="
        isEdit
          ? t('KANBAN.CUSTOM_FIELDS.EDIT_TITLE')
          : t('KANBAN.CUSTOM_FIELDS.NEW_TITLE')
      "
      :header-content="t('KANBAN.CUSTOM_FIELDS.DESCRIPTION')"
    />
    <form
      class="flex flex-col gap-5 px-6 py-5 overflow-y-auto"
      @submit.prevent="onSubmit"
    >
      <Input
        v-model="form.name"
        :label="t('KANBAN.CUSTOM_FIELDS.FORM.NAME_LABEL')"
        :placeholder="t('KANBAN.CUSTOM_FIELDS.FORM.NAME_PLACEHOLDER')"
        autofocus
      />

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.CUSTOM_FIELDS.FORM.TYPE_LABEL') }}
        </span>
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="type in FIELD_TYPES"
            :key="type"
            type="button"
            class="flex flex-col items-center gap-1.5 px-3 py-2.5 rounded-lg border transition-colors"
            :class="
              form.field_type === type
                ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-7'
            "
            @click="form.field_type = type"
          >
            <Icon
              :icon="
                {
                  text: 'i-lucide-text',
                  number: 'i-lucide-hash',
                  date: 'i-lucide-calendar',
                  single_select: 'i-lucide-list',
                  multi_select: 'i-lucide-list-checks',
                }[type]
              "
              class="size-4"
            />
            <span class="text-[11px] font-medium">
              {{ t(`KANBAN.CUSTOM_FIELDS.TYPES.${type.toUpperCase()}`) }}
            </span>
          </button>
        </div>
      </div>

      <div v-if="isSelectType" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.CUSTOM_FIELDS.FORM.CHOICES_LABEL') }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <span
            v-for="choice in form.options.choices"
            :key="choice"
            class="inline-flex items-center gap-1.5 pl-2.5 pr-1.5 py-1 rounded-full bg-n-alpha-2 ring-1 ring-inset ring-n-weak text-[12px] text-n-slate-12"
          >
            {{ choice }}
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-ruby-11"
              @click="removeChoice(choice)"
            >
              <span class="i-lucide-x size-3" />
            </button>
          </span>
        </div>
        <div
          class="flex items-center gap-2 px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus-within:ring-n-brand"
        >
          <input
            v-model="choiceDraft"
            type="text"
            :placeholder="t('KANBAN.CUSTOM_FIELDS.FORM.CHOICE_PLACEHOLDER')"
            class="flex-1 bg-transparent text-sm text-n-slate-12 focus:outline-none"
            @keydown.enter.prevent="addChoice"
          />
          <button
            type="button"
            class="text-[12px] font-semibold text-n-teal-11 hover:text-n-teal-12 disabled:opacity-50 cursor-pointer"
            :disabled="!choiceDraft.trim()"
            @click="addChoice"
          >
            {{ t('KANBAN.CUSTOM_FIELDS.FORM.ADD_CHOICE') }}
          </button>
        </div>
      </div>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          v-model="form.required"
          type="checkbox"
          class="size-4 rounded border-n-weak"
        />
        {{ t('KANBAN.CUSTOM_FIELDS.FORM.REQUIRED_LABEL') }}
      </label>

      <footer class="flex justify-end gap-2 pt-2">
        <Button
          faded
          slate
          type="button"
          :label="t('KANBAN.CUSTOM_FIELDS.CANCEL')"
          @click="emit('close')"
        />
        <Button
          type="submit"
          :label="
            t(
              isEdit
                ? 'KANBAN.CUSTOM_FIELDS.SAVE'
                : 'KANBAN.CUSTOM_FIELDS.CREATE'
            )
          "
          :disabled="!isValid"
        />
      </footer>
    </form>
  </div>
</template>
