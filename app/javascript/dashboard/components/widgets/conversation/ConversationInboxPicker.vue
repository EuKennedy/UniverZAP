<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store.js';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';

// UniverZAP: the agent picks which of their inboxes feed the conversation
// list, so one queue holds several channels at once. Kept in ui_settings
// (conversation_inbox_ids), empty = every inbox they can see.
const { uiSettings, updateUISettings } = useUISettings();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const inboxes = useMapGetter('inboxes/getInboxes');

const sortedInboxes = computed(() =>
  [...inboxes.value].sort((a, b) => a.name.localeCompare(b.name))
);

const savedIds = computed(() => {
  const ids = uiSettings.value.conversation_inbox_ids || [];
  return ids.filter(id => inboxes.value.some(inbox => inbox.id === id));
});

// On an inbox route the list shows that inbox, whatever was picked.
const activeIds = computed(() => (route.params.inbox_id ? [] : savedIds.value));

const isOpen = ref(false);
const draft = ref([]);

const allChecked = computed(
  () => draft.value.length === sortedInboxes.value.length
);

const pickedLabel = computed(() => {
  const count = activeIds.value.length;
  return count === 1
    ? t('CHAT_LIST.INBOX_PICKER.BUTTON_ONE')
    : t('CHAT_LIST.INBOX_PICKER.BUTTON_MANY', { count });
});

function open() {
  draft.value = savedIds.value.length
    ? [...savedIds.value]
    : sortedInboxes.value.map(inbox => inbox.id);
  isOpen.value = true;
}

function close() {
  isOpen.value = false;
}

function toggleOpen() {
  if (isOpen.value) close();
  else open();
}

function toggleInbox(id, checked) {
  draft.value = checked
    ? [...draft.value, id]
    : draft.value.filter(draftId => draftId !== id);
}

function toggleAll(checked) {
  draft.value = checked ? sortedInboxes.value.map(inbox => inbox.id) : [];
}

function apply() {
  // Every inbox checked is the same as none picked: an inbox the agent joins
  // later shows up without coming back here.
  updateUISettings({
    conversation_inbox_ids: allChecked.value ? [] : [...draft.value],
  });
  // An inbox route always shows that one inbox; the pick lives on the list.
  if (route.params.inbox_id) {
    router.push({
      name: 'home',
      params: { accountId: route.params.accountId },
    });
  }
  close();
}
</script>

<template>
  <div class="flex">
    <NextButton
      v-tooltip.top-end="$t('CHAT_LIST.INBOX_PICKER.TOOLTIP')"
      icon="i-lucide-inbox"
      :color="activeIds.length ? 'teal' : 'slate'"
      faded
      xs
      @click="toggleOpen"
    >
      <span v-if="activeIds.length" class="truncate">{{ pickedLabel }}</span>
      <template v-else>
        <span class="2xl:hidden">
          {{ $t('CHAT_LIST.INBOX_PICKER.BUTTON_SHORT') }}
        </span>
        <span class="hidden 2xl:inline">
          {{ $t('CHAT_LIST.INBOX_PICKER.BUTTON') }}
        </span>
      </template>
    </NextButton>
    <div
      v-if="isOpen"
      v-on-click-outside="close"
      class="absolute z-40 flex flex-col mt-1 overflow-hidden border shadow-lg top-full ltr:right-3 rtl:left-3 w-72 max-h-[70vh] rounded-xl border-n-weak bg-n-alpha-3 backdrop-blur-[100px]"
    >
      <div class="px-4 pt-3 pb-2">
        <p class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('CHAT_LIST.INBOX_PICKER.TITLE') }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ $t('CHAT_LIST.INBOX_PICKER.DESCRIPTION') }}
        </p>
      </div>
      <label
        class="flex items-center gap-2.5 px-4 py-2 cursor-pointer hover:bg-n-alpha-2"
      >
        <Checkbox
          :model-value="allChecked"
          :indeterminate="!!draft.length && !allChecked"
          @update:model-value="toggleAll"
        />
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('CHAT_LIST.INBOX_PICKER.ALL') }}
        </span>
        <span class="text-xs ltr:ml-auto rtl:mr-auto text-n-slate-10">
          {{
            $t('CHAT_LIST.INBOX_PICKER.SELECTED', {
              selected: draft.length,
              total: sortedInboxes.length,
            })
          }}
        </span>
      </label>
      <div class="flex-1 min-h-0 py-1 overflow-y-auto border-t border-n-weak">
        <label
          v-for="inbox in sortedInboxes"
          :key="inbox.id"
          class="flex items-center gap-2.5 px-4 py-1.5 cursor-pointer hover:bg-n-alpha-2"
        >
          <Checkbox
            :model-value="draft.includes(inbox.id)"
            @update:model-value="checked => toggleInbox(inbox.id, checked)"
          />
          <ChannelIcon :inbox="inbox" class="size-4 shrink-0 text-n-slate-11" />
          <span class="text-sm truncate text-n-slate-12" :title="inbox.name">
            {{ inbox.name }}
          </span>
        </label>
      </div>
      <div
        class="flex items-center justify-end gap-2 px-4 py-3 border-t border-n-weak"
      >
        <NextButton
          :label="$t('CHAT_LIST.INBOX_PICKER.CANCEL')"
          slate
          faded
          xs
          @click="close"
        />
        <NextButton
          :label="$t('CHAT_LIST.INBOX_PICKER.APPLY')"
          :disabled="!draft.length"
          teal
          xs
          @click="apply"
        />
      </div>
    </div>
  </div>
</template>
