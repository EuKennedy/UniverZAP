<script setup>
/**
 * As pastas das campanhas, como a barra lateral de um gerenciador de arquivos:
 * "Todas", "Sem pasta" e as pastas do salão, cada uma com a contagem. Criar e
 * renomear acontecem no lugar, sem modal, porque é uma palavra só.
 */
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import CampaignsAPI from 'dashboard/api/whatsappStatusCampaigns';
import {
  apiErrorMessage,
  backgroundClass,
  STATUS_BACKGROUNDS,
} from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // '' = todas, 'none' = sem pasta, id = pasta.
  modelValue: { type: [String, Number], default: '' },
  refreshKey: { type: Number, default: 0 },
});

const emit = defineEmits(['update:modelValue', 'loaded']);

const { t } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.CAMPAIGNS.FOLDERS.${key}`);

const folders = ref([]);
const meta = ref({ unfiled_count: 0, total_count: 0 });
const isCreating = ref(false);
const editingId = ref(null);
const draftName = ref('');

const select = value => emit('update:modelValue', value);

const fetchFolders = async () => {
  try {
    const { data } = await CampaignsAPI.folders();
    folders.value = data.payload || [];
    meta.value = data.meta || meta.value;
    emit('loaded', folders.value);
  } catch {
    folders.value = [];
  }
};

const startCreate = () => {
  editingId.value = null;
  draftName.value = '';
  isCreating.value = true;
};

const startRename = folder => {
  isCreating.value = false;
  editingId.value = folder.id;
  draftName.value = folder.name;
};

const cancel = () => {
  isCreating.value = false;
  editingId.value = null;
};

// A cor da pasta nova vem da paleta, em rodízio: dá para distinguir as pastas
// de relance sem pedir mais uma escolha a quem só quer organizar.
const nextColor = () =>
  STATUS_BACKGROUNDS[folders.value.length % STATUS_BACKGROUNDS.length].value;

const submit = async () => {
  const name = draftName.value.trim();
  if (!name) return cancel();
  try {
    if (editingId.value) {
      await CampaignsAPI.updateFolder(editingId.value, { name });
    } else {
      const { data } = await CampaignsAPI.createFolder({
        name,
        color: nextColor(),
      });
      select(data.id);
    }
    cancel();
    await fetchFolders();
  } catch (error) {
    useAlert(apiErrorMessage(error, t('WHATSAPP_PROFILE.ERRORS.GENERIC')));
  }
  return null;
};

const remove = async folder => {
  try {
    await CampaignsAPI.removeFolder(folder.id);
    if (props.modelValue === folder.id) select('');
    useAlert(label('DELETED'));
    await fetchFolders();
  } catch (error) {
    useAlert(apiErrorMessage(error, t('WHATSAPP_PROFILE.ERRORS.GENERIC')));
  }
};

const itemClass = active =>
  active
    ? 'bg-n-alpha-2 text-n-slate-12'
    : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12';

watch(() => props.refreshKey, fetchFolders);
onMounted(fetchFolders);
</script>

<template>
  <nav class="flex flex-col gap-1" data-testid="campaign-folders">
    <span
      class="px-2 pb-1 text-[10px] font-semibold tracking-wider uppercase text-n-slate-10"
    >
      {{ label('TITLE') }}
    </span>
    <button
      type="button"
      class="flex gap-2 items-center px-2.5 py-2 text-[13px] rounded-lg"
      :class="itemClass(modelValue === '')"
      data-testid="folder-all"
      @click="select('')"
    >
      <span class="i-lucide-layers size-4" />
      <span class="flex-1 text-start">{{ label('ALL') }}</span>
      <span class="text-[11px] text-n-slate-10">{{ meta.total_count }}</span>
    </button>
    <button
      type="button"
      class="flex gap-2 items-center px-2.5 py-2 text-[13px] rounded-lg"
      :class="itemClass(modelValue === 'none')"
      data-testid="folder-none"
      @click="select('none')"
    >
      <span class="i-lucide-inbox size-4" />
      <span class="flex-1 text-start">{{ label('UNFILED') }}</span>
      <span class="text-[11px] text-n-slate-10">{{ meta.unfiled_count }}</span>
    </button>

    <div class="my-1 h-px bg-n-weak" />

    <div
      v-for="folder in folders"
      :key="folder.id"
      class="flex items-center rounded-lg group"
      :class="itemClass(modelValue === folder.id)"
      data-testid="folder-item"
    >
      <form
        v-if="editingId === folder.id"
        class="flex flex-1 px-1.5 py-1"
        @submit.prevent="submit"
      >
        <input
          v-model="draftName"
          class="!mb-0 !h-7 w-full !px-2 text-[13px] rounded-md border-0 outline outline-1 outline-n-brand/50 bg-n-surface-1 text-n-slate-12"
          :aria-label="label('NAME')"
          maxlength="60"
          @keydown.esc="cancel"
          @blur="submit"
        />
      </form>
      <template v-else>
        <button
          type="button"
          class="flex flex-1 gap-2 items-center px-2.5 py-2 min-w-0 text-[13px]"
          @click="select(folder.id)"
          @dblclick="startRename(folder)"
        >
          <span
            class="rounded-sm size-3 shrink-0"
            :class="backgroundClass(folder.color)"
          />
          <span class="flex-1 truncate text-start">{{ folder.name }}</span>
          <span class="text-[11px] text-n-slate-10 group-hover:hidden">
            {{ folder.campaigns_count }}
          </span>
        </button>
        <span class="hidden gap-0.5 pe-1 group-hover:flex">
          <Button
            ghost
            slate
            size="xs"
            icon="i-lucide-pencil"
            :aria-label="label('RENAME')"
            @click="startRename(folder)"
          />
          <Button
            ghost
            ruby
            size="xs"
            icon="i-lucide-trash-2"
            :aria-label="label('DELETE')"
            data-testid="folder-delete"
            @click="remove(folder)"
          />
        </span>
      </template>
    </div>

    <form v-if="isCreating" class="px-1.5 py-1" @submit.prevent="submit">
      <input
        v-model="draftName"
        class="!mb-0 !h-8 w-full !px-2.5 text-[13px] rounded-md border-0 outline outline-1 outline-n-brand/50 bg-n-surface-1 text-n-slate-12"
        :placeholder="label('NAME_PLACEHOLDER')"
        :aria-label="label('NAME')"
        maxlength="60"
        data-testid="folder-name"
        @keydown.esc="cancel"
        @blur="submit"
      />
    </form>
    <Button
      v-else
      ghost
      slate
      size="sm"
      class="justify-start"
      icon="i-lucide-folder-plus"
      :label="label('NEW')"
      data-testid="folder-new"
      @click="startCreate"
    />
  </nav>
</template>
