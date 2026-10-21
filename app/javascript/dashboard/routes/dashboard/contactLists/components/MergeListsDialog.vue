<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ContactListsAPI from 'dashboard/api/contactLists';
import { useAlert } from 'dashboard/composables';
import { SOURCE_META } from '../helpers/lists';

const props = defineProps({
  lists: { type: Array, default: () => [] },
});
const emit = defineEmits(['merged']);

const { t } = useI18n();

const dialogRef = ref(null);
const selected = ref([]);
const name = ref('');
const isSaving = ref(false);

const canMerge = computed(() => selected.value.length >= 2);
const suggestedName = computed(() =>
  props.lists
    .filter(list => selected.value.includes(list.id))
    .map(list => list.name)
    .join(' + ')
    .slice(0, 120)
);

const open = (preselected = []) => {
  selected.value = [...preselected];
  name.value = '';
  dialogRef.value?.open();
};

const toggle = id => {
  selected.value = selected.value.includes(id)
    ? selected.value.filter(item => item !== id)
    : [...selected.value, id];
};

const merge = async () => {
  if (!canMerge.value) {
    useAlert(t('CONTACT_LISTS.MERGE.NEED_TWO'));
    return;
  }
  isSaving.value = true;
  try {
    const { data } = await ContactListsAPI.merge({
      listIds: selected.value,
      name: name.value.trim() || suggestedName.value,
    });
    useAlert(t('CONTACT_LISTS.MERGE.SUCCESS'));
    dialogRef.value?.close();
    emit('merged', data);
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CONTACT_LISTS.DETAIL.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACT_LISTS.MERGE.TITLE')"
    :description="t('CONTACT_LISTS.MERGE.HINT')"
    :confirm-button-label="t('CONTACT_LISTS.MERGE.SUBMIT')"
    :cancel-button-label="t('CONTACT_LISTS.MERGE.CANCEL')"
    :disable-confirm-button="!canMerge"
    :is-loading="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="merge"
  >
    <div class="flex flex-col gap-3" data-testid="merge-dialog">
      <div
        class="flex flex-col overflow-y-auto rounded-xl border divide-y max-h-72 border-n-weak divide-n-weak"
      >
        <label
          v-for="list in lists"
          :key="list.id"
          class="flex items-center gap-3 px-4 py-2.5 cursor-pointer hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            :checked="selected.includes(list.id)"
            @change="toggle(list.id)"
          />
          <span
            class="flex items-center justify-center rounded-md size-6 shrink-0"
            :class="SOURCE_META[list.source]?.tone"
          >
            <span class="size-3.5" :class="SOURCE_META[list.source]?.icon" />
          </span>
          <span class="flex-1 text-sm truncate text-n-slate-12">
            {{ list.name }}
          </span>
          <span class="text-[11px] tabular-nums text-n-slate-10">
            {{
              t(
                'CONTACT_LISTS.LIST.MEMBERS',
                { count: list.members_count },
                list.members_count
              )
            }}
          </span>
        </label>
      </div>
      <span class="text-xs text-n-slate-11">
        {{ t('CONTACT_LISTS.MERGE.SELECTED', { count: selected.length }) }}
      </span>
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONTACT_LISTS.MERGE.NAME') }}
        </span>
        <input
          v-model="name"
          type="text"
          maxlength="120"
          :placeholder="suggestedName"
          class="w-full h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
        />
      </label>
    </div>
  </Dialog>
</template>
