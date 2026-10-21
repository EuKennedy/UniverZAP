<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ContactListsAPI from 'dashboard/api/contactLists';
import { useAlert } from 'dashboard/composables';
import { filterLists } from '../helpers/lists';

const emit = defineEmits(['started']);

// Os grupos das conexões WAHA. Extrair só LÊ da WAHA; grupo que já tem lista
// mostra "Atualizar lista" (marca quem entrou e quem saiu).
const { t } = useI18n();

const dialogRef = ref(null);
const groups = ref([]);
const query = ref('');
const isLoading = ref(false);
const busyId = ref(null);

const visible = computed(() =>
  filterLists(groups.value, { query: query.value })
);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await ContactListsAPI.groups();
    groups.value = data.payload;
  } catch {
    groups.value = [];
  } finally {
    isLoading.value = false;
  }
};

const open = () => {
  query.value = '';
  dialogRef.value?.open();
  load();
};

const extract = async group => {
  busyId.value = group.display_id;
  try {
    const { data } = await ContactListsAPI.extractGroup(group.display_id);
    useAlert(t('CONTACT_LISTS.GROUPS.STARTED'));
    dialogRef.value?.close();
    emit('started', data);
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CONTACT_LISTS.GROUPS.ERROR'));
  } finally {
    busyId.value = null;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACT_LISTS.GROUPS.TITLE')"
    :description="t('CONTACT_LISTS.GROUPS.HINT')"
    :show-confirm-button="false"
    :cancel-button-label="t('CONTACT_LISTS.CREATE.CANCEL')"
    width="xl"
    overflow-y-auto
  >
    <div class="flex flex-col gap-3" data-testid="group-picker">
      <label class="relative">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-3.5 start-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="search"
          :placeholder="t('CONTACT_LISTS.GROUPS.SEARCH')"
          class="w-full h-9 !ps-8 pe-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
        />
      </label>
      <div
        class="flex flex-col overflow-y-auto rounded-xl border divide-y max-h-80 border-n-weak divide-n-weak"
      >
        <p
          v-if="!isLoading && !visible.length"
          class="px-4 py-8 m-0 text-sm text-center text-n-slate-11"
        >
          {{ t('CONTACT_LISTS.GROUPS.EMPTY') }}
        </p>
        <div
          v-for="group in visible"
          :key="`${group.inbox_id}-${group.display_id}`"
          class="flex items-center gap-3 px-4 py-3"
          data-testid="group-row"
        >
          <Avatar :src="group.thumbnail" :name="group.name" :size="32" />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ group.name }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ group.inbox_name }}
              <template v-if="group.list_id">
                ·
                {{
                  t('CONTACT_LISTS.GROUPS.HAS_LIST', {
                    count: group.list_members_count,
                  })
                }}
              </template>
            </span>
          </div>
          <Button
            size="sm"
            :variant="group.list_id ? 'outline' : 'solid'"
            :color="group.list_id ? 'slate' : undefined"
            :icon="
              group.list_id ? 'i-lucide-refresh-cw' : 'i-lucide-users-round'
            "
            :label="
              group.list_id
                ? t('CONTACT_LISTS.GROUPS.REFRESH')
                : t('CONTACT_LISTS.GROUPS.EXTRACT')
            "
            :is-loading="busyId === group.display_id"
            @click="extract(group)"
          />
        </div>
      </div>
      <p
        class="flex gap-2 items-start px-3 py-2.5 m-0 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        <span class="i-lucide-shield-alert size-4 shrink-0" />
        {{ t('CONTACT_LISTS.GROUPS.CONSENT_NOTE') }}
      </p>
    </div>
  </Dialog>
</template>
