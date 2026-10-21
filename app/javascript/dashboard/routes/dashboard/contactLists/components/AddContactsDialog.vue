<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ContactAPI from 'dashboard/api/contacts';
import ContactListsAPI from 'dashboard/api/contactLists';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  listId: { type: [Number, String], required: true },
});
const emit = defineEmits(['added']);

const { t } = useI18n();

const dialogRef = ref(null);
const query = ref('');
const results = ref([]);
const selected = ref([]);
const isSearching = ref(false);
const isSaving = ref(false);

const selectedIds = computed(() => selected.value.map(contact => contact.id));

const search = debounce(async () => {
  isSearching.value = true;
  try {
    const { data } = query.value.trim()
      ? await ContactAPI.search(query.value.trim())
      : await ContactAPI.get(1);
    results.value = data.payload || [];
  } catch {
    results.value = [];
  } finally {
    isSearching.value = false;
  }
}, 300);

watch(query, search);

const open = () => {
  query.value = '';
  selected.value = [];
  dialogRef.value?.open();
  search();
};

const toggle = contact => {
  selected.value = selectedIds.value.includes(contact.id)
    ? selected.value.filter(item => item.id !== contact.id)
    : [...selected.value, contact];
};

const submit = async () => {
  if (!selected.value.length) return;
  isSaving.value = true;
  try {
    const { data } = await ContactListsAPI.addMembers(
      props.listId,
      selectedIds.value
    );
    useAlert(t('CONTACT_LISTS.ADD.ADDED', { count: data.added }, data.added));
    dialogRef.value?.close();
    emit('added', data);
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
    :title="t('CONTACT_LISTS.ADD.TITLE')"
    :confirm-button-label="t('CONTACT_LISTS.ADD.SUBMIT')"
    :cancel-button-label="t('CONTACT_LISTS.ADD.CANCEL')"
    :disable-confirm-button="!selected.length"
    :is-loading="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-3" data-testid="add-contacts-dialog">
      <input
        v-model="query"
        type="search"
        :placeholder="t('CONTACT_LISTS.ADD.SEARCH')"
        class="w-full h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
      />
      <div
        class="flex flex-col overflow-y-auto rounded-xl border divide-y max-h-72 border-n-weak divide-n-weak"
      >
        <p
          v-if="!isSearching && !results.length"
          class="px-4 py-6 m-0 text-sm text-center text-n-slate-11"
        >
          {{ t('CONTACT_LISTS.ADD.EMPTY') }}
        </p>
        <label
          v-for="contact in results"
          :key="contact.id"
          class="flex items-center gap-3 px-4 py-2 cursor-pointer hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            :checked="selectedIds.includes(contact.id)"
            @change="toggle(contact)"
          />
          <Avatar :src="contact.thumbnail" :name="contact.name" :size="24" />
          <span class="flex-1 text-sm truncate text-n-slate-12">
            {{ contact.name }}
          </span>
          <span class="text-xs tabular-nums text-n-slate-10">
            {{ contact.phone_number }}
          </span>
        </label>
      </div>
      <span class="text-xs text-n-slate-11">
        {{ t('CONTACT_LISTS.ADD.SELECTED', { count: selected.length }) }}
      </span>
    </div>
  </Dialog>
</template>
