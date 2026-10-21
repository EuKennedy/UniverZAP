<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactListsAPI from 'dashboard/api/contactLists';
import { useAlert } from 'dashboard/composables';
import { previewCsv } from '../helpers/lists';

const props = defineProps({
  listId: { type: [Number, String], required: true },
});
const emit = defineEmits(['imported']);

// Telefones de um CSV ou colados. "Nunca falaram com o salão" vem marcado:
// uma planilha fria é o caso comum, e o disparo pede confirmação para eles.
const { t } = useI18n();

const dialogRef = ref(null);
const fileInput = ref(null);
const content = ref('');
const cold = ref(true);
const isSaving = ref(false);

const preview = computed(() => previewCsv(content.value));

const open = () => {
  content.value = '';
  cold.value = true;
  dialogRef.value?.open();
};

const onFile = async event => {
  const [file] = event.target.files || [];
  if (file) content.value = await file.text();
  event.target.value = '';
};

const submit = async () => {
  if (!content.value.trim()) return;
  isSaving.value = true;
  try {
    const { data } = await ContactListsAPI.importCsv(props.listId, {
      content: content.value,
      cold: cold.value,
    });
    useAlert(
      t('CONTACT_LISTS.IMPORT.RESULT', {
        added: data.added,
        created: data.created,
        invalid: data.invalid,
      })
    );
    dialogRef.value?.close();
    emit('imported', data);
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CONTACT_LISTS.IMPORT.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACT_LISTS.IMPORT.TITLE')"
    :description="t('CONTACT_LISTS.IMPORT.HINT')"
    :confirm-button-label="t('CONTACT_LISTS.IMPORT.SUBMIT')"
    :cancel-button-label="t('CONTACT_LISTS.IMPORT.CANCEL')"
    :disable-confirm-button="!content.trim()"
    :is-loading="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-3" data-testid="import-csv-dialog">
      <textarea
        v-model="content"
        rows="6"
        :placeholder="t('CONTACT_LISTS.IMPORT.PLACEHOLDER')"
        class="w-full px-3 py-2 font-mono text-xs rounded-lg border resize-y bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
        data-testid="import-csv-content"
      />
      <div class="flex items-center gap-2">
        <Button
          variant="outline"
          color="slate"
          size="sm"
          icon="i-lucide-upload"
          :label="t('CONTACT_LISTS.IMPORT.FILE')"
          @click="fileInput?.click()"
        />
        <input
          ref="fileInput"
          type="file"
          accept=".csv,.txt,text/csv,text/plain"
          class="hidden"
          @change="onFile"
        />
      </div>
      <div
        v-if="preview.length"
        class="flex flex-col gap-1 px-3 py-2 rounded-lg bg-n-alpha-1"
      >
        <span
          class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-10"
        >
          {{ t('CONTACT_LISTS.IMPORT.PREVIEW') }}
        </span>
        <code
          v-for="(line, index) in preview"
          :key="index"
          class="text-xs truncate text-n-slate-11"
        >
          {{ line }}
        </code>
      </div>
      <label
        class="flex gap-2.5 items-start p-3 rounded-xl border cursor-pointer border-n-weak"
      >
        <input v-model="cold" type="checkbox" class="mt-0.5" />
        <span class="flex flex-col gap-0.5">
          <span class="text-[13px] font-medium text-n-slate-12">
            {{ t('CONTACT_LISTS.IMPORT.COLD') }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ t('CONTACT_LISTS.IMPORT.COLD_HINT') }}
          </span>
        </span>
      </label>
    </div>
  </Dialog>
</template>
