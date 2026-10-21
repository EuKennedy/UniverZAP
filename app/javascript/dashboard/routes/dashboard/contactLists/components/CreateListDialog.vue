<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ContactListsAPI from 'dashboard/api/contactLists';
import { useAlert } from 'dashboard/composables';
import { SOURCE_META } from '../helpers/lists';

const emit = defineEmits(['created']);

// Lista nova: manual (vazia), CSV (abre a importação em seguida) ou filtro
// (foto de quem tem as etiquetas hoje). Grupo tem o próprio diálogo.
const ORIGINS = ['manual', 'csv', 'filter'];

const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');

const dialogRef = ref(null);
const name = ref('');
const description = ref('');
const source = ref('manual');
const labelIds = ref([]);
const isSaving = ref(false);

const canSave = computed(
  () =>
    name.value.trim().length > 0 &&
    (source.value !== 'filter' || labelIds.value.length > 0)
);

const open = (initialSource = 'manual') => {
  name.value = '';
  description.value = '';
  source.value = initialSource;
  labelIds.value = [];
  dialogRef.value?.open();
};

const toggleLabel = id => {
  labelIds.value = labelIds.value.includes(id)
    ? labelIds.value.filter(item => item !== id)
    : [...labelIds.value, id];
};

const save = async () => {
  if (!canSave.value) return;
  isSaving.value = true;
  try {
    const { data } = await ContactListsAPI.create({
      name: name.value.trim(),
      description: description.value.trim(),
      source: source.value,
      label_ids: labelIds.value,
    });
    useAlert(t('CONTACT_LISTS.CREATE.SUCCESS'));
    dialogRef.value?.close();
    emit('created', data);
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CONTACT_LISTS.CREATE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });

const fieldClass =
  'w-full h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACT_LISTS.CREATE.TITLE')"
    :confirm-button-label="t('CONTACT_LISTS.CREATE.SUBMIT')"
    :cancel-button-label="t('CONTACT_LISTS.CREATE.CANCEL')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="save"
  >
    <div class="flex flex-col gap-4" data-testid="create-list-dialog">
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONTACT_LISTS.CREATE.NAME') }}
        </span>
        <input
          v-model="name"
          type="text"
          maxlength="120"
          :placeholder="t('CONTACT_LISTS.CREATE.NAME_PLACEHOLDER')"
          :class="fieldClass"
          data-testid="create-list-name"
        />
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONTACT_LISTS.CREATE.DESCRIPTION') }}
        </span>
        <textarea
          v-model="description"
          rows="2"
          :placeholder="t('CONTACT_LISTS.CREATE.DESCRIPTION_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm rounded-lg border resize-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
        />
      </label>
      <div class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONTACT_LISTS.CREATE.SOURCE') }}
        </span>
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="origin in ORIGINS"
            :key="origin"
            type="button"
            class="flex flex-col items-start gap-2 p-3 text-start rounded-xl border transition-colors"
            :class="
              source === origin
                ? 'border-n-brand bg-n-brand/5'
                : 'border-n-weak hover:border-n-slate-6'
            "
            :data-testid="`create-list-source-${origin}`"
            @click="source = origin"
          >
            <span
              class="flex items-center justify-center rounded-lg size-7"
              :class="SOURCE_META[origin].tone"
            >
              <span class="size-4" :class="SOURCE_META[origin].icon" />
            </span>
            <span class="text-[13px] font-medium text-n-slate-12">
              {{ t(`CONTACT_LISTS.SOURCE.${origin.toUpperCase()}`) }}
            </span>
          </button>
        </div>
        <p class="m-0 text-xs text-n-slate-10">
          {{ t(`CONTACT_LISTS.CREATE.SOURCE_HINT.${source.toUpperCase()}`) }}
        </p>
      </div>
      <div v-if="source === 'filter'" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONTACT_LISTS.CREATE.LABELS') }}
        </span>
        <div v-if="labels.length" class="flex flex-wrap gap-2">
          <button
            v-for="label in labels"
            :key="label.id"
            type="button"
            class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium transition-colors"
            :class="
              labelIds.includes(label.id)
                ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
            "
            @click="toggleLabel(label.id)"
          >
            <span
              class="rounded-sm size-2"
              :style="{ backgroundColor: label.color }"
            />
            {{ label.title }}
          </button>
        </div>
        <p v-else class="m-0 text-xs text-n-slate-10">
          {{ t('CONTACT_LISTS.CREATE.LABELS_EMPTY') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
