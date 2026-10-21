<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactListsAPI from 'dashboard/api/contactLists';

// Na conversa de um grupo do WhatsApp: extrai os participantes para uma lista
// de distribuição (só lê da WAHA) ou atualiza a lista que já existe.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const POLL_MS = 3000;

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const list = ref(null);
const isBusy = ref(false);
let pollTimer = null;

const isImporting = computed(() => list.value?.status === 'importing');

const stopPolling = () => {
  clearInterval(pollTimer);
  pollTimer = null;
};

const loadList = async () => {
  try {
    const { data } = await ContactListsAPI.groups();
    const group = data.payload.find(
      item => String(item.display_id) === String(props.conversationId)
    );
    list.value = group?.list_id
      ? (await ContactListsAPI.show(group.list_id)).data
      : null;
  } catch {
    list.value = null;
  }
};

watch(isImporting, importing => {
  if (importing && !pollTimer) pollTimer = setInterval(loadList, POLL_MS);
  else if (!importing) stopPolling();
});
watch(() => props.conversationId, loadList, { immediate: true });
onBeforeUnmount(stopPolling);

const extract = async () => {
  isBusy.value = true;
  try {
    const { data } = await ContactListsAPI.extractGroup(props.conversationId);
    list.value = data;
    useAlert(t('CONTACT_LISTS.PANEL.STARTED'));
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CONTACT_LISTS.GROUPS.ERROR'));
  } finally {
    isBusy.value = false;
  }
};

const openList = () =>
  router.push(
    accountScopedRoute('contact_lists_show', { listId: list.value.id })
  );
</script>

<template>
  <div
    class="flex flex-col gap-2.5 p-3 mx-2 mb-3 rounded-xl border border-n-weak bg-n-solid-1"
    data-testid="group-list-card"
  >
    <div class="flex gap-2.5 items-center">
      <span
        class="flex justify-center items-center rounded-lg size-8 shrink-0 bg-brand-gradient text-[#06131C]"
      >
        <span class="i-lucide-list-checks size-4" />
      </span>
      <div class="flex flex-col min-w-0">
        <span class="text-[13px] font-semibold text-n-slate-12">
          {{ t('CONTACT_LISTS.PANEL.TITLE') }}
        </span>
        <span class="text-[11px] text-n-slate-11">
          <template v-if="isImporting">
            {{ t('CONTACT_LISTS.PANEL.IMPORTING') }}
          </template>
          <template v-else-if="list?.status === 'failed'">
            {{ t('CONTACT_LISTS.PANEL.FAILED') }}
          </template>
          <template v-else-if="list">
            {{
              t(
                'CONTACT_LISTS.PANEL.MEMBERS',
                { count: list.members_count },
                list.members_count
              )
            }}
          </template>
          <template v-else>{{ t('CONTACT_LISTS.PANEL.BODY') }}</template>
        </span>
      </div>
    </div>
    <div class="flex flex-wrap gap-2">
      <Button
        size="sm"
        :variant="list ? 'outline' : 'solid'"
        :color="list ? 'slate' : undefined"
        :icon="list ? 'i-lucide-refresh-cw' : 'i-lucide-users-round'"
        :label="
          list
            ? t('CONTACT_LISTS.PANEL.REFRESH')
            : t('CONTACT_LISTS.PANEL.EXTRACT')
        "
        :is-loading="isBusy || isImporting"
        data-testid="group-list-extract"
        @click="extract"
      />
      <Button
        v-if="list"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-arrow-up-right"
        :label="t('CONTACT_LISTS.PANEL.OPEN')"
        @click="openList"
      />
    </div>
  </div>
</template>
