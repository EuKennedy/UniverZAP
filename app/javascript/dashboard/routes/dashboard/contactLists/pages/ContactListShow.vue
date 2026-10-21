<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { debounce } from '@chatwoot/utils';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import ContactListsAPI from 'dashboard/api/contactLists';
import BroadcastsAPI from 'dashboard/api/broadcasts';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ImportCsvDialog from '../components/ImportCsvDialog.vue';
import AddContactsDialog from '../components/AddContactsDialog.vue';
import {
  BADGE_TONES,
  MEMBER_FILTERS,
  SOURCE_META,
  downloadBlob,
  memberBadges,
  relativeTime,
  summaryCards,
} from '../helpers/lists';

const props = defineProps({
  listId: { type: [String, Number], required: true },
});

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const POLL_MS = 3000;

const list = ref(null);
const members = ref([]);
const meta = ref({ total: 0, page: 1, per_page: 50 });
const filter = ref('all');
const query = ref('');
const page = ref(1);
const isLoading = ref(false);
const busy = ref('');
const isEditing = ref(false);
const draft = ref({ name: '', description: '' });
let pollTimer = null;

const importDialog = ref(null);
const addDialog = ref(null);

const summary = computed(() => list.value?.summary || {});
const cards = computed(() => summaryCards(summary.value));
const pages = computed(() =>
  Math.max(1, Math.ceil(meta.value.total / meta.value.per_page))
);
const isGroup = computed(() => list.value?.source === 'group');
const isImporting = computed(() => list.value?.status === 'importing');
const sourceMeta = computed(() => SOURCE_META[list.value?.source] || {});
const lastRun = computed(() => list.value?.last_run || null);

const loadList = async () => {
  const { data } = await ContactListsAPI.show(props.listId);
  list.value = data;
};

const loadMembers = async () => {
  const { data } = await ContactListsAPI.members(props.listId, {
    page: page.value,
    filter: filter.value,
    q: query.value,
  });
  members.value = data.payload;
  meta.value = data.meta;
};

const reload = async ({ quiet = false } = {}) => {
  if (!quiet) isLoading.value = true;
  try {
    await Promise.all([loadList(), loadMembers()]);
  } catch {
    if (!quiet) useAlert(t('CONTACT_LISTS.DETAIL.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const stopPolling = () => {
  clearInterval(pollTimer);
  pollTimer = null;
};

watch(isImporting, importing => {
  if (importing && !pollTimer) {
    pollTimer = setInterval(() => reload({ quiet: true }), POLL_MS);
  } else if (!importing) stopPolling();
});

const searchMembers = debounce(() => {
  page.value = 1;
  loadMembers();
}, 300);
watch(query, searchMembers);
watch(filter, () => {
  page.value = 1;
  loadMembers();
});
watch(page, loadMembers);

// Cada ação da barra mostra o carregamento só no próprio botão.
const run = async (key, action) => {
  busy.value = key;
  try {
    await action();
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CONTACT_LISTS.DETAIL.ERROR'));
  } finally {
    busy.value = '';
  }
};

const refreshFromGroup = () =>
  run('refresh', async () => {
    const { data } = await ContactListsAPI.refresh(props.listId);
    list.value = data;
    useAlert(t('CONTACT_LISTS.GROUPS.STARTED'));
  });

const deduplicate = () =>
  run('dedupe', async () => {
    const { data } = await ContactListsAPI.deduplicate(props.listId);
    useAlert(
      t(
        'CONTACT_LISTS.DETAIL.DEDUPLICATED',
        { count: data.removed },
        data.removed
      )
    );
    await reload({ quiet: true });
  });

const exportCsv = () =>
  run('export', async () => {
    const { data } = await ContactListsAPI.exportCsv(props.listId);
    downloadBlob(data, `lista-${props.listId}.csv`);
  });

const useInBroadcast = () =>
  run('broadcast', async () => {
    const { data } = await BroadcastsAPI.create({
      name: t('CONTACT_LISTS.DETAIL.BROADCAST_NAME', {
        name: list.value.name,
      }),
      audience: { contact_list_ids: [list.value.id] },
    });
    router.push(
      accountScopedRoute('broadcasts_show', { broadcastId: data.id })
    );
  });

const removeList = () =>
  run('delete', async () => {
    const question = t('CONTACT_LISTS.LIST.DELETE_CONFIRM', {
      name: list.value.name,
    });
    // eslint-disable-next-line no-alert
    if (!window.confirm(question)) return;
    await ContactListsAPI.delete(props.listId);
    useAlert(t('CONTACT_LISTS.LIST.DELETE_SUCCESS'));
    router.push(accountScopedRoute('contact_lists_index'));
  });

const removeMember = member =>
  run(`member-${member.id}`, async () => {
    // eslint-disable-next-line no-alert
    if (
      !window.confirm(
        t('CONTACT_LISTS.DETAIL.REMOVE_CONFIRM', { name: member.name })
      )
    )
      return;
    await ContactListsAPI.removeMembers(props.listId, [member.id]);
    useAlert(t('CONTACT_LISTS.DETAIL.REMOVED'));
    await reload({ quiet: true });
  });

const startEdit = () => {
  draft.value = {
    name: list.value.name,
    description: list.value.description || '',
  };
  isEditing.value = true;
};

const saveEdit = () =>
  run('save', async () => {
    await ContactListsAPI.update(props.listId, {
      name: draft.value.name.trim(),
      description: draft.value.description.trim(),
    });
    isEditing.value = false;
    useAlert(t('CONTACT_LISTS.DETAIL.SAVED'));
    await loadList();
  });

const openConversation = () =>
  router.push(
    accountScopedRoute('inbox_conversation', {
      conversation_id: list.value.conversation_display_id,
    })
  );

const goBack = () => router.push(accountScopedRoute('contact_lists_index'));

const joinedLabel = member =>
  member.status === 'left'
    ? relativeTime(member.left_at, locale.value)
    : relativeTime(member.joined_at, locale.value);

onMounted(async () => {
  await reload();
  if (route.query.import) importDialog.value?.open();
});
onBeforeUnmount(stopPolling);

const controlClass =
  'h-9 px-3 rounded-lg bg-n-solid-2 border border-n-weak text-[13px] text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex flex-col gap-4 px-8 py-6 border-b border-n-weak"
      data-testid="list-header"
    >
      <button
        type="button"
        class="flex items-center gap-1 text-xs w-fit text-n-slate-11 hover:text-n-slate-12"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left size-3.5" />
        {{ t('CONTACT_LISTS.DETAIL.BACK') }}
      </button>
      <div v-if="list" class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="flex items-center justify-center rounded-xl shadow-lg size-11 shrink-0 bg-brand-gradient text-[#06131C] shadow-n-brand/20"
          >
            <span class="size-5" :class="sourceMeta.icon" />
          </span>
          <div v-if="isEditing" class="flex flex-col flex-1 max-w-xl gap-2">
            <input
              v-model="draft.name"
              type="text"
              maxlength="120"
              :class="controlClass"
            />
            <textarea
              v-model="draft.description"
              rows="2"
              class="px-3 py-2 text-[13px] rounded-lg border resize-none bg-n-solid-2 border-n-weak text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0"
            />
            <div class="flex gap-2">
              <Button
                size="sm"
                :label="t('CONTACT_LISTS.DETAIL.SAVE')"
                :is-loading="busy === 'save'"
                :disabled="!draft.name.trim()"
                @click="saveEdit"
              />
              <Button
                size="sm"
                variant="ghost"
                color="slate"
                :label="t('CONTACT_LISTS.DETAIL.CANCEL')"
                @click="isEditing = false"
              />
            </div>
          </div>
          <div v-else class="flex flex-col min-w-0 gap-1">
            <div class="flex flex-wrap items-center gap-2">
              <h1
                class="m-0 text-xl font-bold tracking-tight truncate text-n-slate-12"
              >
                {{ list.name }}
              </h1>
              <button
                type="button"
                class="flex items-center justify-center rounded-md size-6 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                :title="t('CONTACT_LISTS.DETAIL.EDIT')"
                @click="startEdit"
              >
                <span class="i-lucide-pencil size-3.5" />
              </button>
            </div>
            <p
              v-if="list.description"
              class="m-0 max-w-2xl text-[13px] text-n-slate-11"
            >
              {{ list.description }}
            </p>
            <div class="flex flex-wrap items-center gap-1.5 mt-1">
              <span
                class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-medium"
                :class="sourceMeta.tone"
              >
                <span class="size-3" :class="sourceMeta.icon" />
                {{ t(`CONTACT_LISTS.SOURCE.${list.source.toUpperCase()}`) }}
              </span>
              <span
                v-if="list.label"
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-tag size-3" />
                {{ t('CONTACT_LISTS.DETAIL.LABEL', { label: list.label }) }}
              </span>
              <span
                v-if="lastRun && (lastRun.joined || lastRun.left)"
                class="text-[11px] text-n-slate-10"
              >
                {{
                  t('CONTACT_LISTS.LIST.UPDATED', {
                    when: relativeTime(list.refreshed_at, locale),
                  })
                }}
                ·
                {{
                  t('CONTACT_LISTS.DETAIL.LAST_RUN', {
                    joined: lastRun.joined || 0,
                    left: lastRun.left || 0,
                  })
                }}
              </span>
              <button
                v-if="list.conversation_display_id"
                type="button"
                class="text-[11px] text-n-iris-11 hover:underline"
                @click="openConversation"
              >
                {{ t('CONTACT_LISTS.DETAIL.GROUP_LINK') }}
              </button>
            </div>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            v-if="isGroup"
            icon="i-lucide-refresh-cw"
            :label="t('CONTACT_LISTS.DETAIL.REFRESH_GROUP')"
            :is-loading="busy === 'refresh' || isImporting"
            data-testid="list-refresh-group"
            @click="refreshFromGroup"
          />
          <Button
            variant="outline"
            color="slate"
            icon="i-lucide-send"
            :label="t('CONTACT_LISTS.DETAIL.USE_IN_BROADCAST')"
            :is-loading="busy === 'broadcast'"
            :disabled="!summary.active"
            @click="useInBroadcast"
          />
          <Button
            variant="ghost"
            color="slate"
            icon="i-lucide-trash-2"
            :label="t('CONTACT_LISTS.LIST.DELETE')"
            :is-loading="busy === 'delete'"
            @click="removeList"
          />
        </div>
      </div>
    </header>

    <div v-if="list" class="flex flex-col flex-1 gap-4 px-8 py-6">
      <div
        v-if="isImporting"
        class="flex items-center gap-2 px-4 py-3 text-[13px] rounded-xl bg-n-teal-3 text-n-teal-11"
        data-testid="list-importing"
      >
        <span class="i-lucide-loader-circle size-4 animate-spin shrink-0" />
        {{ t('CONTACT_LISTS.DETAIL.IMPORTING_BANNER') }}
      </div>
      <div
        v-else-if="list.status === 'failed'"
        class="flex items-center gap-2 px-4 py-3 text-[13px] rounded-xl bg-n-ruby-3 text-n-ruby-11"
      >
        <span class="i-lucide-circle-alert size-4 shrink-0" />
        {{
          t('CONTACT_LISTS.DETAIL.FAILED_BANNER', { error: list.last_error })
        }}
      </div>

      <div
        class="grid gap-3 grid-cols-[repeat(auto-fit,minmax(10rem,1fr))]"
        data-testid="list-summary"
      >
        <button
          v-for="card in cards"
          :key="card.key"
          type="button"
          class="flex gap-3 items-center px-4 py-3.5 text-start rounded-xl border transition-colors bg-n-solid-1"
          :class="
            filter === card.key.toLowerCase()
              ? 'border-n-brand'
              : 'border-n-weak hover:border-n-slate-6'
          "
          @click="
            filter = MEMBER_FILTERS.includes(card.key.toLowerCase())
              ? card.key.toLowerCase()
              : 'active'
          "
        >
          <span
            class="flex justify-center items-center rounded-lg size-9 shrink-0"
            :class="card.tone"
          >
            <span class="size-[18px]" :class="card.icon" />
          </span>
          <span class="flex flex-col min-w-0">
            <span
              class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-11"
            >
              {{ t(`CONTACT_LISTS.DETAIL.SUMMARY.${card.key}`) }}
            </span>
            <span class="text-lg font-bold leading-tight text-n-slate-12">
              {{ card.value }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ t(`CONTACT_LISTS.DETAIL.SUMMARY_HINT.${card.key}`) }}
            </span>
          </span>
        </button>
      </div>

      <p
        v-if="summary.unconsented"
        class="flex gap-2 items-start px-4 py-3 m-0 text-[13px] rounded-xl bg-n-amber-3 text-n-amber-11"
        data-testid="list-cold-banner"
      >
        <span class="i-lucide-shield-alert size-4 shrink-0 mt-0.5" />
        {{
          t('CONTACT_LISTS.DETAIL.COLD_BANNER', { count: summary.unconsented })
        }}
      </p>

      <div
        class="flex flex-wrap items-center gap-2 px-4 py-3 rounded-xl border border-n-weak bg-n-solid-1"
        data-testid="list-toolbar"
      >
        <label class="relative flex-1 min-w-44 max-w-72">
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-3.5 start-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="search"
            :placeholder="t('CONTACT_LISTS.DETAIL.SEARCH')"
            class="w-full !ps-8"
            :class="controlClass"
          />
        </label>
        <div class="flex flex-wrap gap-1 p-1 rounded-lg bg-n-alpha-1">
          <button
            v-for="item in MEMBER_FILTERS"
            :key="item"
            type="button"
            class="px-2.5 py-1 text-[13px] font-medium rounded-md transition-colors"
            :class="
              filter === item
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`member-filter-${item}`"
            @click="filter = item"
          >
            {{ t(`CONTACT_LISTS.DETAIL.FILTER.${item.toUpperCase()}`) }}
          </button>
        </div>
        <div class="flex flex-wrap items-center gap-1 ms-auto">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-user-plus"
            :label="t('CONTACT_LISTS.DETAIL.ADD_CONTACTS')"
            @click="addDialog?.open()"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-file-up"
            :label="t('CONTACT_LISTS.DETAIL.IMPORT_CSV')"
            @click="importDialog?.open()"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-copy-minus"
            :label="t('CONTACT_LISTS.DETAIL.DEDUPLICATE')"
            :is-loading="busy === 'dedupe'"
            @click="deduplicate"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-download"
            :label="t('CONTACT_LISTS.DETAIL.EXPORT')"
            :is-loading="busy === 'export'"
            @click="exportCsv"
          />
        </div>
      </div>

      <div class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1">
        <div
          v-if="!members.length && !isLoading"
          class="flex flex-col items-center gap-2 py-16 text-center"
          data-testid="members-empty"
        >
          <span
            class="flex items-center justify-center size-12 rounded-2xl bg-n-brand/10 text-n-teal-11"
          >
            <span class="i-lucide-users size-6" />
          </span>
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('CONTACT_LISTS.DETAIL.NO_MEMBERS') }}
          </h3>
          <p class="m-0 text-xs text-n-slate-11">
            {{ t('CONTACT_LISTS.DETAIL.NO_MEMBERS_BODY') }}
          </p>
        </div>
        <table v-else class="w-full text-[13px]" data-testid="members-table">
          <thead>
            <tr class="border-b border-n-weak text-n-slate-11">
              <th class="px-4 py-2.5 font-medium text-start">
                {{ t('CONTACT_LISTS.DETAIL.COLUMN.CONTACT') }}
              </th>
              <th class="px-4 py-2.5 font-medium text-start">
                {{ t('CONTACT_LISTS.DETAIL.COLUMN.PHONE') }}
              </th>
              <th class="px-4 py-2.5 font-medium text-start">
                {{ t('CONTACT_LISTS.DETAIL.COLUMN.STATUS') }}
              </th>
              <th class="px-4 py-2.5 font-medium text-start">
                {{ t('CONTACT_LISTS.DETAIL.COLUMN.JOINED') }}
              </th>
              <th class="w-10" />
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="member in members"
              :key="member.id"
              class="group hover:bg-n-alpha-1"
              :class="member.status === 'left' ? 'opacity-60' : ''"
              data-testid="member-row"
            >
              <td class="px-4 py-2.5">
                <div class="flex items-center min-w-0 gap-2.5">
                  <Avatar
                    :src="member.thumbnail"
                    :name="member.name || '?'"
                    :size="28"
                  />
                  <span class="font-medium truncate text-n-slate-12">
                    {{
                      member.name || t('CONTACT_LISTS.DETAIL.UNKNOWN_MEMBER')
                    }}
                  </span>
                </div>
              </td>
              <td class="px-4 py-2.5 tabular-nums text-n-slate-11">
                {{ member.phone || '—' }}
              </td>
              <td class="px-4 py-2.5">
                <div class="flex flex-wrap gap-1">
                  <span
                    v-for="badge in memberBadges(member)"
                    :key="badge"
                    class="px-1.5 py-0.5 rounded-md text-[10px] font-semibold"
                    :class="BADGE_TONES[badge]"
                  >
                    {{ t(`CONTACT_LISTS.BADGE.${badge}`) }}
                  </span>
                </div>
              </td>
              <td class="px-4 py-2.5 text-[11px] text-n-slate-10">
                {{ joinedLabel(member) }}
              </td>
              <td class="px-2">
                <button
                  type="button"
                  class="flex items-center justify-center rounded-lg opacity-0 size-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-11 group-hover:opacity-100"
                  :title="t('CONTACT_LISTS.DETAIL.REMOVE')"
                  @click="removeMember(member)"
                >
                  <span class="i-lucide-user-minus size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <div
          v-if="pages > 1"
          class="flex items-center justify-between px-4 py-2.5 border-t border-n-weak text-xs text-n-slate-11"
        >
          <span>{{ t('CONTACT_LISTS.DETAIL.PAGE', { page, pages }) }}</span>
          <div class="flex gap-1">
            <Button
              size="xs"
              variant="outline"
              color="slate"
              :label="t('CONTACT_LISTS.DETAIL.PREV')"
              :disabled="page <= 1"
              @click="page -= 1"
            />
            <Button
              size="xs"
              variant="outline"
              color="slate"
              :label="t('CONTACT_LISTS.DETAIL.NEXT')"
              :disabled="page >= pages"
              @click="page += 1"
            />
          </div>
        </div>
      </div>
    </div>

    <ImportCsvDialog
      ref="importDialog"
      :list-id="listId"
      @imported="reload({ quiet: true })"
    />
    <AddContactsDialog
      ref="addDialog"
      :list-id="listId"
      @added="reload({ quiet: true })"
    />
  </div>
</template>
