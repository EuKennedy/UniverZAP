<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { LocalStorage } from 'shared/helpers/localStorage';

import ContactListsAPI from 'dashboard/api/contactLists';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CreateListDialog from '../components/CreateListDialog.vue';
import GroupPickerDialog from '../components/GroupPickerDialog.vue';
import MergeListsDialog from '../components/MergeListsDialog.vue';
import {
  SOURCES,
  SOURCE_META,
  filterLists,
  relativeTime,
} from '../helpers/lists';

const { t, locale } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const VIEWS = [
  { value: 'cards', icon: 'i-lucide-layout-grid' },
  { value: 'table', icon: 'i-lucide-table-2' },
];
const PREFS_KEY = 'uz_contact_lists';
// Enquanto uma extração de grupo roda, a página confere de tempos em tempos.
const POLL_MS = 4000;

const readPrefs = () => {
  try {
    return LocalStorage.get(PREFS_KEY) || {};
  } catch {
    return {};
  }
};

const lists = ref([]);
const stats = ref(null);
const isLoading = ref(false);
const query = ref('');
const source = ref('');
const view = ref(readPrefs().view || 'cards');
let pollTimer = null;

const createDialog = ref(null);
const groupDialog = ref(null);
const mergeDialog = ref(null);

watch(view, value => {
  try {
    LocalStorage.set(PREFS_KEY, { view: value });
  } catch {
    // Sem armazenamento local, a preferência vale só nesta visita.
  }
});

const filtered = computed(() =>
  filterLists(lists.value, { query: query.value, source: source.value })
);
const hasFilters = computed(() => Boolean(query.value || source.value));
const hasImporting = computed(() =>
  lists.value.some(list => list.status === 'importing')
);

const statCards = computed(() => {
  const data = stats.value || {};
  return [
    {
      key: 'LISTS',
      icon: 'i-lucide-list-checks',
      tone: 'bg-n-brand/10 text-n-teal-11',
      value: data.lists ?? '–',
      hint: t('CONTACT_LISTS.STATS.LISTS_HINT', {
        count: data.group_lists ?? 0,
      }),
    },
    {
      key: 'CONTACTS',
      icon: 'i-lucide-users',
      tone: 'bg-n-iris-3 text-n-iris-11',
      value: data.contacts ?? '–',
      hint: t('CONTACT_LISTS.STATS.CONTACTS_HINT'),
    },
    {
      key: 'SENDABLE',
      icon: 'i-lucide-send',
      tone: 'bg-n-teal-3 text-n-teal-11',
      value: data.sendable ?? '–',
      hint: t('CONTACT_LISTS.STATS.SENDABLE_HINT'),
    },
    {
      key: 'COLD',
      icon: 'i-lucide-shield-alert',
      tone: 'bg-n-amber-3 text-n-amber-11',
      value: data.unconsented ?? '–',
      hint: t('CONTACT_LISTS.STATS.COLD_HINT'),
    },
    {
      key: 'NO_PHONE',
      icon: 'i-lucide-phone-off',
      tone: 'bg-n-ruby-3 text-n-ruby-11',
      value: data.no_phone ?? '–',
      hint: t('CONTACT_LISTS.STATS.NO_PHONE_HINT'),
    },
  ];
});

const load = async ({ quiet = false } = {}) => {
  if (!quiet) isLoading.value = true;
  try {
    const [{ data }, { data: statsData }] = await Promise.all([
      ContactListsAPI.get(),
      ContactListsAPI.stats(),
    ]);
    lists.value = data.payload;
    stats.value = statsData;
  } catch {
    if (!quiet) useAlert(t('CONTACT_LISTS.LIST.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const stopPolling = () => {
  clearInterval(pollTimer);
  pollTimer = null;
};

watch(hasImporting, importing => {
  if (importing && !pollTimer) {
    pollTimer = setInterval(() => load({ quiet: true }), POLL_MS);
  } else if (!importing) stopPolling();
});

const openList = list =>
  router.push(accountScopedRoute('contact_lists_show', { listId: list.id }));

const onCreated = list => {
  if (list.source === 'csv') {
    router.push(
      accountScopedRoute(
        'contact_lists_show',
        { listId: list.id },
        { import: '1' }
      )
    );
    return;
  }
  openList(list);
};

const onStarted = () => load({ quiet: true });

const removeList = async list => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('CONTACT_LISTS.LIST.DELETE_CONFIRM', { name: list.name }))
  )
    return;
  try {
    await ContactListsAPI.delete(list.id);
    useAlert(t('CONTACT_LISTS.LIST.DELETE_SUCCESS'));
    load({ quiet: true });
  } catch {
    useAlert(t('CONTACT_LISTS.LIST.DELETE_ERROR'));
  }
};

const clearFilters = () => {
  query.value = '';
  source.value = '';
};

const updatedLabel = list =>
  list.refreshed_at
    ? t('CONTACT_LISTS.LIST.UPDATED', {
        when: relativeTime(list.refreshed_at, locale.value),
      })
    : t('CONTACT_LISTS.LIST.CREATED', {
        when: relativeTime(list.created_at, locale.value),
      });

const membersLabel = list =>
  t(
    'CONTACT_LISTS.LIST.MEMBERS',
    { count: list.members_count },
    list.members_count
  );

onMounted(() => {
  store.dispatch('labels/get');
  load();
});
onBeforeUnmount(stopPolling);

const controlClass =
  'h-9 px-3 rounded-lg bg-n-solid-2 border border-n-weak text-[13px] text-n-slate-12 focus:outline-none focus:border-n-brand !mb-0';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex flex-wrap items-center justify-between gap-4 px-8 py-6 border-b border-n-weak"
    >
      <div class="flex items-center gap-3">
        <span
          class="flex items-center justify-center rounded-xl shadow-lg size-11 shrink-0 bg-brand-gradient text-[#06131C] shadow-n-brand/20"
        >
          <span class="i-lucide-list-checks size-5" />
        </span>
        <div class="flex flex-col gap-0.5">
          <h1 class="m-0 text-xl font-bold tracking-tight text-n-slate-12">
            {{ t('CONTACT_LISTS.TITLE') }}
          </h1>
          <p class="m-0 max-w-2xl text-[13px] text-n-slate-11">
            {{ t('CONTACT_LISTS.SUBTITLE') }}
          </p>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-refresh-cw"
          :label="t('CONTACT_LISTS.REFRESH')"
          :is-loading="isLoading"
          @click="load()"
        />
        <Button
          variant="outline"
          color="slate"
          icon="i-lucide-combine"
          :label="t('CONTACT_LISTS.MERGE')"
          :disabled="lists.length < 2"
          data-testid="lists-merge"
          @click="mergeDialog?.open()"
        />
        <Button
          variant="outline"
          color="slate"
          icon="i-lucide-users-round"
          :label="t('CONTACT_LISTS.EXTRACT_GROUP')"
          data-testid="lists-extract-group"
          @click="groupDialog?.open()"
        />
        <Button
          icon="i-lucide-plus"
          :label="t('CONTACT_LISTS.NEW')"
          data-testid="lists-new"
          @click="createDialog?.open()"
        />
      </div>
    </header>

    <div class="flex flex-col flex-1 gap-4 px-8 py-6">
      <div
        class="grid gap-3 grid-cols-[repeat(auto-fit,minmax(11rem,1fr))]"
        data-testid="lists-stats"
      >
        <div
          v-for="card in statCards"
          :key="card.key"
          class="flex gap-3 items-center px-4 py-3.5 rounded-xl border border-n-weak bg-n-solid-1"
        >
          <span
            class="flex justify-center items-center rounded-lg size-9 shrink-0"
            :class="card.tone"
          >
            <span class="size-[18px]" :class="card.icon" />
          </span>
          <div class="flex flex-col min-w-0">
            <span
              class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-11"
            >
              {{ t(`CONTACT_LISTS.STATS.${card.key}`) }}
            </span>
            <span class="text-lg font-bold leading-tight text-n-slate-12">
              {{ card.value }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ card.hint }}
            </span>
          </div>
        </div>
      </div>

      <div
        class="flex flex-wrap items-center gap-2 px-4 py-3 rounded-xl border border-n-weak bg-n-solid-1"
        data-testid="lists-toolbar"
      >
        <label class="relative flex-1 min-w-44 max-w-72">
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-3.5 start-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="search"
            :placeholder="t('CONTACT_LISTS.SEARCH')"
            class="w-full !ps-8"
            :class="controlClass"
            data-testid="lists-search"
          />
        </label>
        <select v-model="source" :class="controlClass" class="!w-48">
          <option value="">{{ t('CONTACT_LISTS.ALL_SOURCES') }}</option>
          <option v-for="item in SOURCES" :key="item" :value="item">
            {{ t(`CONTACT_LISTS.SOURCE.${item.toUpperCase()}`) }}
          </option>
        </select>
        <div class="flex gap-1 p-1 rounded-lg ms-auto bg-n-alpha-1">
          <button
            v-for="option in VIEWS"
            :key="option.value"
            type="button"
            class="flex items-center gap-1.5 px-2.5 py-1 text-[13px] font-medium rounded-md transition-colors"
            :class="
              view === option.value
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`lists-view-${option.value}`"
            @click="view = option.value"
          >
            <span class="size-3.5" :class="option.icon" />
            {{ t(`CONTACT_LISTS.VIEW.${option.value.toUpperCase()}`) }}
          </button>
        </div>
      </div>

      <div
        v-if="hasFilters"
        class="flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
      >
        {{ t('CONTACT_LISTS.LIST.RESULTS', { count: filtered.length }) }}
        <button
          type="button"
          class="px-2 py-0.5 rounded-md text-n-iris-11 hover:bg-n-alpha-2"
          @click="clearFilters"
        >
          {{ t('CONTACT_LISTS.LIST.CLEAR_FILTERS') }}
        </button>
      </div>

      <div
        v-if="!filtered.length && !isLoading"
        class="flex flex-col items-center justify-center gap-3 py-20 text-center"
        data-testid="lists-empty"
      >
        <span
          class="flex items-center justify-center size-16 rounded-2xl bg-n-brand/10 text-n-teal-11"
        >
          <Icon
            :icon="hasFilters ? 'i-lucide-search-x' : 'i-lucide-list-checks'"
            class="size-7"
          />
        </span>
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{
            hasFilters
              ? t('CONTACT_LISTS.LIST.NO_RESULTS_TITLE')
              : t('CONTACT_LISTS.LIST.EMPTY_TITLE')
          }}
        </h3>
        <p class="m-0 max-w-md text-sm text-n-slate-11">
          {{
            hasFilters
              ? t('CONTACT_LISTS.LIST.NO_RESULTS_BODY')
              : t('CONTACT_LISTS.LIST.EMPTY_BODY')
          }}
        </p>
        <Button
          v-if="hasFilters"
          variant="outline"
          color="slate"
          :label="t('CONTACT_LISTS.LIST.CLEAR_FILTERS')"
          @click="clearFilters"
        />
        <div v-else class="flex gap-2">
          <Button
            variant="outline"
            color="slate"
            icon="i-lucide-users-round"
            :label="t('CONTACT_LISTS.EXTRACT_GROUP')"
            @click="groupDialog?.open()"
          />
          <Button
            icon="i-lucide-plus"
            :label="t('CONTACT_LISTS.NEW')"
            @click="createDialog?.open()"
          />
        </div>
      </div>

      <div
        v-else-if="view === 'cards'"
        class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          v-for="list in filtered"
          :key="list.id"
          class="flex flex-col gap-3 p-5 rounded-2xl border transition-all cursor-pointer group bg-n-solid-1 border-n-weak hover:border-n-teal-7 hover:shadow-lg"
          data-testid="list-card"
          @click="openList(list)"
        >
          <div class="flex items-start gap-3">
            <span
              class="flex items-center justify-center rounded-xl size-10 shrink-0"
              :class="SOURCE_META[list.source]?.tone"
            >
              <span class="size-5" :class="SOURCE_META[list.source]?.icon" />
            </span>
            <div class="flex flex-col flex-1 min-w-0 gap-0.5">
              <h3 class="m-0 text-sm font-semibold truncate text-n-slate-12">
                {{ list.name }}
              </h3>
              <span class="text-[11px] truncate text-n-slate-10">
                {{ t(`CONTACT_LISTS.SOURCE.${list.source.toUpperCase()}`) }}
                · {{ updatedLabel(list) }}
              </span>
            </div>
            <button
              type="button"
              class="flex items-center justify-center rounded-lg opacity-0 size-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-11 group-hover:opacity-100"
              :title="t('CONTACT_LISTS.LIST.DELETE')"
              @click.stop="removeList(list)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </div>
          <p
            v-if="list.description"
            class="m-0 text-xs line-clamp-2 text-n-slate-11"
          >
            {{ list.description }}
          </p>
          <div class="flex flex-wrap items-center gap-1.5 mt-auto">
            <span
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-alpha-2 text-n-slate-12 tabular-nums"
            >
              <span class="i-lucide-users size-3" />
              {{ membersLabel(list) }}
            </span>
            <span
              v-if="list.status === 'importing'"
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-teal-3 text-n-teal-11"
            >
              <span class="i-lucide-loader-circle size-3 animate-spin" />
              {{ t('CONTACT_LISTS.LIST.IMPORTING') }}
            </span>
            <span
              v-else-if="list.status === 'failed'"
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-ruby-3 text-n-ruby-11"
            >
              {{ t('CONTACT_LISTS.LIST.FAILED') }}
            </span>
            <span
              v-if="list.no_phone_count"
              class="px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-ruby-3 text-n-ruby-11"
            >
              {{
                t('CONTACT_LISTS.LIST.NO_PHONE_COUNT', {
                  count: list.no_phone_count,
                })
              }}
            </span>
            <span
              v-if="list.left_count"
              class="px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
            >
              {{
                t('CONTACT_LISTS.LIST.LEFT_COUNT', { count: list.left_count })
              }}
            </span>
          </div>
        </article>
      </div>

      <div
        v-else
        class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
      >
        <table class="w-full text-[13px]" data-testid="lists-table">
          <thead>
            <tr class="border-b border-n-weak text-n-slate-11">
              <th class="px-4 py-2.5 text-start font-medium">
                {{ t('CONTACT_LISTS.LIST.COLUMN.NAME') }}
              </th>
              <th class="px-4 py-2.5 text-start font-medium">
                {{ t('CONTACT_LISTS.LIST.COLUMN.SOURCE') }}
              </th>
              <th class="px-4 py-2.5 text-end font-medium">
                {{ t('CONTACT_LISTS.LIST.COLUMN.MEMBERS') }}
              </th>
              <th class="px-4 py-2.5 text-start font-medium">
                {{ t('CONTACT_LISTS.LIST.COLUMN.ISSUES') }}
              </th>
              <th class="px-4 py-2.5 text-start font-medium">
                {{ t('CONTACT_LISTS.LIST.COLUMN.UPDATED') }}
              </th>
              <th class="w-10" />
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="list in filtered"
              :key="list.id"
              class="cursor-pointer group hover:bg-n-alpha-1"
              @click="openList(list)"
            >
              <td class="px-4 py-3">
                <div class="flex flex-col min-w-0">
                  <span class="font-medium truncate text-n-slate-12">
                    {{ list.name }}
                  </span>
                  <span
                    v-if="list.description"
                    class="text-[11px] truncate text-n-slate-10 max-w-80"
                  >
                    {{ list.description }}
                  </span>
                </div>
              </td>
              <td class="px-4 py-3">
                <span
                  class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-medium"
                  :class="SOURCE_META[list.source]?.tone"
                >
                  <span
                    class="size-3"
                    :class="SOURCE_META[list.source]?.icon"
                  />
                  {{ t(`CONTACT_LISTS.SOURCE.${list.source.toUpperCase()}`) }}
                </span>
              </td>
              <td class="px-4 py-3 tabular-nums text-end text-n-slate-12">
                {{ list.members_count }}
              </td>
              <td class="px-4 py-3 text-[11px] text-n-slate-11">
                <span v-if="list.status === 'importing'">
                  {{ t('CONTACT_LISTS.LIST.IMPORTING') }}
                </span>
                <span v-else>
                  {{
                    [
                      list.no_phone_count
                        ? t('CONTACT_LISTS.LIST.NO_PHONE_COUNT', {
                            count: list.no_phone_count,
                          })
                        : '',
                      list.left_count
                        ? t('CONTACT_LISTS.LIST.LEFT_COUNT', {
                            count: list.left_count,
                          })
                        : '',
                    ]
                      .filter(Boolean)
                      .join(' · ') || '—'
                  }}
                </span>
              </td>
              <td class="px-4 py-3 text-[11px] text-n-slate-10">
                {{ updatedLabel(list) }}
              </td>
              <td class="px-2">
                <button
                  type="button"
                  class="flex items-center justify-center rounded-lg opacity-0 size-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-11 group-hover:opacity-100"
                  :title="t('CONTACT_LISTS.LIST.DELETE')"
                  @click.stop="removeList(list)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <CreateListDialog ref="createDialog" @created="onCreated" />
    <GroupPickerDialog ref="groupDialog" @started="onStarted" />
    <MergeListsDialog ref="mergeDialog" :lists="lists" @merged="openList" />
  </div>
</template>
