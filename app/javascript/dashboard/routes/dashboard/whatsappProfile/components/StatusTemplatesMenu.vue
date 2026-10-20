<script setup>
/**
 * Modelos de status: o texto e o visual que se repetem toda semana. Aplicar
 * preenche o compositor; nada é publicado a partir daqui.
 */
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';
import { apiErrorMessage } from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  // O que "Salvar como modelo" grava: o estado atual do compositor.
  current: { type: Object, required: true },
});

const emit = defineEmits(['apply']);

const { t } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.TEMPLATES.${key}`);

const templates = ref([]);
const isOpen = ref(false);
const name = ref('');
const isSaving = ref(false);
const saveError = ref('');
const saveDialogRef = ref(null);

const fetchTemplates = async () => {
  try {
    const { data } = await WhatsAppStatusAPI.templates();
    templates.value = data.payload || [];
  } catch {
    templates.value = [];
  }
};

const apply = template => {
  emit('apply', template);
  isOpen.value = false;
};

const remove = async template => {
  await WhatsAppStatusAPI.removeTemplate(template.id);
  templates.value = templates.value.filter(item => item.id !== template.id);
};

const openSave = () => {
  name.value = '';
  saveError.value = '';
  saveDialogRef.value?.open();
};

const save = async () => {
  isSaving.value = true;
  saveError.value = '';
  try {
    await WhatsAppStatusAPI.createTemplate({
      ...props.current,
      name: name.value.trim(),
    });
    saveDialogRef.value?.close();
    useAlert(label('SAVED'));
    await fetchTemplates();
  } catch (error) {
    saveError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchTemplates);
</script>

<template>
  <div
    v-on-click-outside="() => (isOpen = false)"
    class="flex relative flex-wrap gap-2 items-center"
  >
    <Button
      slate
      faded
      size="sm"
      icon="i-lucide-layout-template"
      :label="label('OPEN')"
      data-testid="templates-toggle"
      @click="isOpen = !isOpen"
    />
    <Button
      ghost
      slate
      size="sm"
      icon="i-lucide-bookmark-plus"
      :label="label('SAVE_CURRENT')"
      :disabled="!current.body"
      data-testid="templates-save"
      @click="openSave"
    />

    <div
      v-if="isOpen"
      class="flex absolute left-0 top-full z-20 flex-col gap-1 p-1 mt-1 w-72 rounded-lg border shadow-lg border-n-weak bg-n-solid-2"
      data-testid="templates-list"
    >
      <p
        v-if="!templates.length"
        class="px-3 py-2 m-0 text-[13px] text-n-slate-11"
      >
        {{ label('EMPTY') }}
      </p>
      <div
        v-for="template in templates"
        :key="template.id"
        class="flex gap-2 items-center rounded-md hover:bg-n-alpha-2"
      >
        <button
          type="button"
          class="flex flex-col flex-1 gap-0.5 px-3 py-2 min-w-0 text-start"
          @click="apply(template)"
        >
          <span class="text-[13px] font-medium truncate text-n-slate-12">
            {{ template.name }}
          </span>
          <span class="text-[12px] truncate text-n-slate-11">
            {{ template.body }}
          </span>
        </button>
        <Button
          ghost
          slate
          size="xs"
          icon="i-lucide-trash-2"
          :aria-label="label('DELETE')"
          @click="remove(template)"
        />
      </div>
    </div>

    <Dialog
      ref="saveDialogRef"
      width="sm"
      :title="label('SAVE_TITLE')"
      :confirm-button-label="label('SAVE')"
      :cancel-button-label="t('WHATSAPP_PROFILE.STATUS.CONFIRM.CANCEL')"
      :is-loading="isSaving"
      :disable-confirm-button="!name.trim()"
      @confirm="save"
    >
      <Input
        v-model="name"
        :label="label('NAME')"
        :placeholder="label('NAME_PLACEHOLDER')"
        :message="saveError"
        :message-type="saveError ? 'error' : 'info'"
      />
    </Dialog>
  </div>
</template>
