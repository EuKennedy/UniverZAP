<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // When set, the modal is in edit mode for an existing channel.
  channel: { type: Object, default: null },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const name = ref('');
const description = ref('');

watch(
  () => props.channel,
  next => {
    name.value = next?.name || '';
    description.value = next?.description || '';
  },
  { immediate: true }
);

const isEdit = computed(() => Boolean(props.channel));
const isValid = computed(() => name.value.trim().length > 0);

// Live preview of the `#slug` the backend will derive from the name so the
// operator isn't surprised by the handle.
const slugPreview = computed(() => {
  const base = name.value
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return base || 'canal';
});

const onSubmit = () => {
  if (!isValid.value) return;
  emit('submit', {
    name: name.value.trim(),
    description: description.value.trim() || null,
  });
};
</script>

<template>
  <div class="flex flex-col w-[440px] max-w-full">
    <woot-modal-header
      :header-title="
        isEdit
          ? t('TEAM_CHAT.CHANNEL.EDIT_TITLE')
          : t('TEAM_CHAT.CHANNEL.NEW_TITLE')
      "
      :header-content="t('TEAM_CHAT.CHANNEL.MODAL_SUBTITLE')"
    />
    <form class="flex flex-col gap-5 px-6 py-5" @submit.prevent="onSubmit">
      <div class="flex flex-col gap-1.5">
        <Input
          v-model="name"
          :label="t('TEAM_CHAT.CHANNEL.NAME_LABEL')"
          :placeholder="t('TEAM_CHAT.CHANNEL.NAME_PLACEHOLDER')"
          autofocus
        />
        <p
          v-if="name.trim()"
          class="text-[11px] text-n-slate-10 inline-flex items-center gap-1"
        >
          <span class="text-n-slate-11">#{{ slugPreview }}</span>
        </p>
      </div>

      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('TEAM_CHAT.CHANNEL.DESCRIPTION_LABEL') }}
        </span>
        <textarea
          v-model="description"
          rows="2"
          :placeholder="t('TEAM_CHAT.CHANNEL.DESCRIPTION_PLACEHOLDER')"
          class="w-full px-3 py-2 rounded-md bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12 resize-none"
        />
      </div>

      <footer class="flex justify-end gap-2 pt-2">
        <Button
          faded
          slate
          type="button"
          :label="t('TEAM_CHAT.CHANNEL.CANCEL')"
          @click="emit('close')"
        />
        <Button
          type="submit"
          teal
          solid
          :label="
            isEdit ? t('TEAM_CHAT.CHANNEL.SAVE') : t('TEAM_CHAT.CHANNEL.CREATE')
          "
          :disabled="!isValid"
        />
      </footer>
    </form>
  </div>
</template>
