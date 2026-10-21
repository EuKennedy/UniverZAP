<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { LocalStorage } from 'shared/helpers/localStorage';

import BroadcastsAPI from 'dashboard/api/broadcasts';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SequencesPanel from '../components/SequencesPanel.vue';
import BroadcastStatsBar from '../components/BroadcastStatsBar.vue';
import {
  COLUMNS,
  PAGE_SIZES,
  STATUSES,
  defaultColumns,
  filterBroadcasts,
  pageWindow,
  paginate,
  progressOf,
  replyRateOf,
  widthClass,
} from '../helpers/broadcastList';

const { t, locale } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const broadcasts = useMapGetter('broadcasts/getBroadcasts');
const uiFlags = useMapGetter('broadcasts/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

// Disparos e sequências moram no mesmo menu: as duas coisas saem pelo número.
const TABS = ['broadcasts', 'sequences'];
const VIEWS = [
  { value: 'cards', icon: 'i-lucide-layout-grid' },
  { value: 'table', icon: 'i-lucide-table-2' },
];
const PREFS_KEY = 'uz_broadcasts_list';

// Preferências de quem usa a tela (visão, colunas, linhas por página).
// localStorage pode faltar (aba anônima): a tela funciona com os padrões.
const readPrefs = () => {
  try {
    return LocalStorage.get(PREFS_KEY) || {};
  } catch {
    return {};
  }
};
const prefs = readPrefs();

const tab = ref('broadcasts');
const view = ref(prefs.view || 'cards');
const visibleColumns = ref(prefs.columns || defaultColumns());
const pageSize = ref(prefs.pageSize || PAGE_SIZES[0]);
const page = ref(1);
const query = ref('');
const status = ref('');
const isColumnsOpen = ref(false);
const statsKey = ref(0);
const stats = ref(null);

const isCreating = ref(false);
const newName = ref('');

watch([view, visibleColumns, pageSize], () => {
  try {
    LocalStorage.set(PREFS_KEY, {
      view: view.value,
      columns: visibleColumns.value,
      pageSize: pageSize.value,
    });
  } catch {
    // Sem armazenamento local, a preferência vale só nesta visita.
  }
});

const filtered = computed(() =>
  filterBroadcasts(broadcasts.value || [], {
    query: query.value,
    status: status.value,
  })
);
const pageData = computed(() =>
  paginate(filtered.value, page.value, pageSize.value)
);
const pages = computed(() =>
  pageWindow(pageData.value.page, pageData.value.totalPages)
);
const hasFilters = computed(() => Boolean(query.value || status.value));

// Filtrar volta para a primeira página.
watch([query, status, pageSize], () => {
  page.value = 1;
});

const subtitle = computed(() => {
  const total = (broadcasts.value || []).length;
  if (!total) return t('BROADCAST.LIST.SUBTITLE');
  return t(
    'BROADCAST.LIST.SUMMARY',
    {
      total,
      running: stats.value?.running ?? 0,
      sequences: stats.value?.sequences_enabled ?? 0,
    },
    total
  );
});

const inboxName = id => (inboxes.value || []).find(i => i.id === id)?.name;
const isColumnVisible = key => visibleColumns.value.includes(key);
const toggleColumn = key => {
  visibleColumns.value = isColumnVisible(key)
    ? visibleColumns.value.filter(column => column !== key)
    : [...visibleColumns.value, key];
};

const statusTone = value =>
  ({
    running: 'text-n-teal-11 bg-n-teal-3',
    scheduled: 'text-n-blue-11 bg-n-blue-3',
    draft: 'text-n-amber-11 bg-n-amber-3',
    completed: 'text-n-slate-11 bg-n-alpha-2',
    paused: 'text-n-ruby-11 bg-n-ruby-3',
  })[value] || 'text-n-slate-11 bg-n-alpha-2';

const formatDate = seconds =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).format(new Date(seconds * 1000));

const progressWidth = item => widthClass(progressOf(item) / 100);

const percentLabel = item => `${progressOf(item)}%`;
const sentLabel = item =>
  `${item.sent_count || 0}/${item.recipients_count || 0}`;

const replyLabel = item => {
  const rate = replyRateOf(item);
  return rate === null ? '–' : `${rate}%`;
};

const refresh = () => {
  store.dispatch('broadcasts/get');
  statsKey.value += 1;
};

onMounted(() => {
  store.dispatch('broadcasts/get');
  store.dispatch('inboxes/get');
});

const openComposer = broadcast => {
  router.push(
    accountScopedRoute('broadcasts_show', { broadcastId: broadcast.id })
  );
};

const startCreate = () => {
  tab.value = 'broadcasts';
  isCreating.value = true;
  newName.value = '';
};

const cancelCreate = () => {
  isCreating.value = false;
  newName.value = '';
};

const submitCreate = async () => {
  const name = newName.value.trim();
  if (!name) return;
  try {
    const created = await store.dispatch('broadcasts/create', {
      name,
      mode: 'waha',
    });
    cancelCreate();
    openComposer(created);
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.LIST.CREATE_ERROR'));
  }
};

const duplicateBroadcast = async broadcast => {
  try {
    const { data } = await BroadcastsAPI.duplicate(broadcast.id);
    useAlert(t('BROADCAST.LIST.DUPLICATED'));
    openComposer(data);
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.LIST.DUPLICATE_ERROR'));
  }
};

const removeBroadcast = async broadcast => {
  const question = t('BROADCAST.LIST.DELETE_CONFIRM', {
    name: broadcast.name,
  });
  // eslint-disable-next-line no-alert
  if (!window.confirm(question)) return;
  try {
    await store.dispatch('broadcasts/delete', broadcast.id);
    useAlert(t('BROADCAST.LIST.DELETE_SUCCESS'));
    statsKey.value += 1;
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.LIST.DELETE_ERROR'));
  }
};

const clearFilters = () => {
  query.value = '';
  status.value = '';
};

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
          <span class="i-lucide-megaphone size-5" />
        </span>
        <div class="flex flex-col gap-0.5">
          <h1 class="m-0 text-xl font-bold tracking-tight text-n-slate-12">
            {{ t('BROADCAST.LIST.TITLE') }}
          </h1>
          <p
            class="m-0 max-w-2xl text-[13px] text-n-slate-11"
            data-testid="page-subtitle"
          >
            {{ subtitle }}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-refresh-cw"
          :label="t('BROADCAST.LIST.REFRESH')"
          :is-loading="uiFlags.isFetching"
          @click="refresh"
        />
        <Button
          icon="i-lucide-plus"
          :label="t('BROADCAST.LIST.NEW')"
          data-testid="broadcast-new"
          @click="startCreate"
        />
      </div>
    </header>

    <div class="flex flex-col gap-4 px-8 pt-6">
      <BroadcastStatsBar
        :refresh-key="statsKey"
        @loaded="data => (stats = data)"
      />

      <nav
        class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1"
        data-testid="broadcast-tabs"
      >
        <button
          v-for="item in TABS"
          :key="item"
          type="button"
          class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
          :class="
            tab === item
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :data-testid="`broadcast-tab-${item}`"
          @click="tab = item"
        >
          {{ t(`BROADCAST.TABS.${item.toUpperCase()}`) }}
        </button>
      </nav>
    </div>

    <div v-if="tab === 'sequences'" class="flex-1 px-8 py-6">
      <SequencesPanel />
    </div>

    <div v-else class="flex flex-col flex-1 gap-3 px-8 py-6">
      <form
        v-if="isCreating"
        class="flex items-center gap-2 max-w-xl"
        @submit.prevent="submitCreate"
      >
        <input
          v-model="newName"
          v-focus
          type="text"
          :placeholder="t('BROADCAST.LIST.NAME_PLACEHOLDER')"
          class="flex-1"
          :class="controlClass"
        />
        <Button
          type="submit"
          :label="t('BROADCAST.LIST.CREATE')"
          :is-loading="uiFlags.isCreating"
        />
        <Button
          variant="ghost"
          color="slate"
          :label="t('BROADCAST.LIST.CANCEL')"
          @click="cancelCreate"
        />
      </form>

      <!-- Toolbar -->
      <div
        class="flex flex-wrap items-center gap-2 px-4 py-3 rounded-xl border border-n-weak bg-n-solid-1"
        data-testid="broadcast-toolbar"
      >
        <label class="relative flex-1 min-w-44 max-w-72">
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-3.5 start-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="search"
            :placeholder="t('BROADCAST.LIST.SEARCH')"
            class="w-full !ps-8"
            :class="controlClass"
            data-testid="broadcast-search"
          />
        </label>
        <select
          v-model="status"
          :class="controlClass"
          class="!w-48"
          data-testid="broadcast-status-filter"
        >
          <option value="">{{ t('BROADCAST.LIST.ALL_STATUSES') }}</option>
          <option v-for="item in STATUSES" :key="item" :value="item">
            {{ t(`BROADCAST.STATUS.${item.toUpperCase()}`) }}
          </option>
        </select>
        <span class="w-px h-5 bg-n-weak" />
        <div v-if="view === 'table'" class="relative">
          <Button
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-columns-3"
            :label="t('BROADCAST.LIST.COLUMNS')"
            data-testid="broadcast-columns"
            @click="isColumnsOpen = !isColumnsOpen"
          />
          <div
            v-if="isColumnsOpen"
            class="absolute z-20 flex flex-col p-1.5 mt-1 rounded-xl border shadow-lg min-w-48 end-0 top-full border-n-weak bg-n-solid-2"
          >
            <span
              class="px-2.5 pt-1 pb-2 text-[10px] font-semibold tracking-wider uppercase text-n-slate-10"
            >
              {{ t('BROADCAST.LIST.VISIBLE_COLUMNS') }}
            </span>
            <label
              v-for="column in COLUMNS"
              :key="column.key"
              class="flex items-center gap-2 px-2.5 py-1.5 text-[13px] rounded-lg cursor-pointer text-n-slate-12 hover:bg-n-alpha-2"
            >
              <input
                type="checkbox"
                :checked="isColumnVisible(column.key)"
                @change="toggleColumn(column.key)"
              />
              {{ t(`BROADCAST.LIST.COLUMN.${column.key.toUpperCase()}`) }}
            </label>
          </div>
        </div>
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
            :data-testid="`broadcast-view-${option.value}`"
            @click="view = option.value"
          >
            <span class="size-3.5" :class="option.icon" />
            {{ t(`BROADCAST.LIST.VIEW.${option.value.toUpperCase()}`) }}
          </button>
        </div>
      </div>

      <div
        v-if="hasFilters"
        class="flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
        data-testid="broadcast-active-filters"
      >
        {{ t('BROADCAST.LIST.RESULTS', { count: filtered.length }) }}
        <button
          type="button"
          class="px-2 py-0.5 rounded-md text-n-blue-11 hover:bg-n-alpha-2"
          @click="clearFilters"
        >
          {{ t('BROADCAST.LIST.CLEAR_FILTERS') }}
        </button>
      </div>

      <!-- Empty states -->
      <div
        v-if="!filtered.length && !uiFlags.isFetching"
        class="flex flex-col items-center justify-center gap-3 py-20 text-center"
        data-testid="broadcast-empty"
      >
        <span
          class="flex items-center justify-center size-16 rounded-2xl bg-n-brand/10 text-n-teal-11"
        >
          <Icon
            :icon="hasFilters ? 'i-lucide-search-x' : 'i-lucide-megaphone'"
            class="size-7"
          />
        </span>
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{
            hasFilters
              ? t('BROADCAST.LIST.NO_RESULTS_TITLE')
              : t('BROADCAST.LIST.EMPTY_TITLE')
          }}
        </h3>
        <p class="m-0 max-w-md text-sm text-n-slate-11">
          {{
            hasFilters
              ? t('BROADCAST.LIST.NO_RESULTS_BODY')
              : t('BROADCAST.LIST.EMPTY_BODY')
          }}
        </p>
        <Button
          v-if="hasFilters"
          variant="outline"
          color="slate"
          :label="t('BROADCAST.LIST.CLEAR_FILTERS')"
          @click="clearFilters"
        />
        <Button
          v-else
          icon="i-lucide-plus"
          :label="t('BROADCAST.LIST.NEW')"
          @click="startCreate"
        />
      </div>

      <!-- Cards -->
      <div
        v-else-if="view === 'cards'"
        class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          v-for="broadcast in pageData.items"
          :key="broadcast.id"
          class="flex flex-col gap-3 p-5 rounded-2xl border transition-all cursor-pointer group bg-n-solid-1 border-n-weak hover:border-n-teal-7 hover:shadow-lg"
          data-testid="broadcast-card"
          @click="openComposer(broadcast)"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="flex flex-col min-w-0 gap-1">
              <h3 class="m-0 text-sm font-semibold truncate text-n-slate-12">
                {{ broadcast.name }}
              </h3>
              <span class="text-[11px] truncate text-n-slate-10">
                {{
                  inboxName(broadcast.inbox_id) || t('BROADCAST.LIST.NO_INBOX')
                }}
              </span>
            </div>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] font-medium shrink-0"
              :class="statusTone(broadcast.status)"
            >
              {{ t(`BROADCAST.STATUS.${broadcast.status.toUpperCase()}`) }}
            </span>
          </div>

          <div class="flex flex-col gap-1.5">
            <div
              class="flex items-center justify-between text-[11px] text-n-slate-11"
            >
              <span>
                {{
                  t('BROADCAST.LIST.PROGRESS', {
                    sent: broadcast.sent_count || 0,
                    total: broadcast.recipients_count || 0,
                  })
                }}
              </span>
              <span class="tabular-nums">{{ percentLabel(broadcast) }}</span>
            </div>
            <div class="overflow-hidden h-1.5 rounded-full bg-n-alpha-2">
              <div
                class="h-full rounded-full bg-n-teal-9"
                :class="progressWidth(broadcast)"
              />
            </div>
          </div>

          <div class="grid grid-cols-3 gap-2 text-center">
            <div class="flex flex-col py-1.5 rounded-lg bg-n-alpha-1">
              <span class="text-sm font-semibold tabular-nums text-n-slate-12">
                {{ replyLabel(broadcast) }}
              </span>
              <span class="text-[10px] text-n-slate-10">
                {{ t('BROADCAST.LIST.COLUMN.REPLIED') }}
              </span>
            </div>
            <div class="flex flex-col py-1.5 rounded-lg bg-n-alpha-1">
              <span class="text-sm font-semibold tabular-nums text-n-slate-12">
                {{ broadcast.skipped_count || 0 }}
              </span>
              <span class="text-[10px] text-n-slate-10">
                {{ t('BROADCAST.LIST.COLUMN.SKIPPED') }}
              </span>
            </div>
            <div class="flex flex-col py-1.5 rounded-lg bg-n-alpha-1">
              <span
                class="text-sm font-semibold tabular-nums"
                :class="
                  broadcast.failed_count ? 'text-n-ruby-11' : 'text-n-slate-12'
                "
              >
                {{ broadcast.failed_count || 0 }}
              </span>
              <span class="text-[10px] text-n-slate-10">
                {{ t('BROADCAST.LIST.COLUMN.FAILED') }}
              </span>
            </div>
          </div>

          <p
            v-if="broadcast.pause_reason === 'failures'"
            class="m-0 px-2.5 py-1.5 rounded-lg text-[11px] bg-n-ruby-3 text-n-ruby-11"
          >
            {{ t('BROADCAST.LIST.PAUSED_BY_FAILURES') }}
          </p>

          <div class="flex items-center justify-end gap-1 mt-auto" @click.stop>
            <Button
              v-tooltip.top="t('BROADCAST.LIST.DUPLICATE')"
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-copy"
              data-testid="broadcast-duplicate"
              @click="duplicateBroadcast(broadcast)"
            />
            <Button
              v-tooltip.top="t('BROADCAST.LIST.DELETE')"
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="removeBroadcast(broadcast)"
            />
          </div>
        </article>
      </div>

      <!-- Table -->
      <div
        v-else
        class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1"
        data-testid="broadcast-table"
      >
        <table class="w-full text-[13px]">
          <thead>
            <tr
              class="text-[10px] font-semibold tracking-wider text-left uppercase border-b border-n-weak text-n-slate-10"
            >
              <th class="px-4 py-2.5">{{ t('BROADCAST.LIST.COLUMN.NAME') }}</th>
              <template v-for="column in COLUMNS" :key="column.key">
                <th v-if="isColumnVisible(column.key)" class="px-3 py-2.5">
                  {{ t(`BROADCAST.LIST.COLUMN.${column.key.toUpperCase()}`) }}
                </th>
              </template>
              <th class="px-3 py-2.5" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="broadcast in pageData.items"
              :key="broadcast.id"
              class="border-b cursor-pointer last:border-b-0 border-n-weak hover:bg-n-alpha-1"
              data-testid="broadcast-row"
              @click="openComposer(broadcast)"
            >
              <td class="px-4 py-2.5 font-medium text-n-slate-12">
                {{ broadcast.name }}
              </td>
              <td v-if="isColumnVisible('status')" class="px-3 py-2.5">
                <span
                  class="px-2 py-0.5 rounded-full text-[11px] font-medium"
                  :class="statusTone(broadcast.status)"
                >
                  {{ t(`BROADCAST.STATUS.${broadcast.status.toUpperCase()}`) }}
                </span>
              </td>
              <td
                v-if="isColumnVisible('inbox')"
                class="px-3 py-2.5 text-n-slate-11"
              >
                {{ inboxName(broadcast.inbox_id) || '–' }}
              </td>
              <td
                v-if="isColumnVisible('progress')"
                class="px-3 py-2.5 tabular-nums text-n-slate-11"
              >
                {{ sentLabel(broadcast) }}
              </td>
              <td
                v-if="isColumnVisible('replied')"
                class="px-3 py-2.5 tabular-nums text-n-slate-11"
              >
                {{ replyLabel(broadcast) }}
              </td>
              <td
                v-if="isColumnVisible('skipped')"
                class="px-3 py-2.5 tabular-nums text-n-slate-11"
              >
                {{ broadcast.skipped_count || 0 }}
              </td>
              <td
                v-if="isColumnVisible('failed')"
                class="px-3 py-2.5 tabular-nums"
                :class="
                  broadcast.failed_count ? 'text-n-ruby-11' : 'text-n-slate-11'
                "
              >
                {{ broadcast.failed_count || 0 }}
              </td>
              <td
                v-if="isColumnVisible('created')"
                class="px-3 py-2.5 tabular-nums text-n-slate-11"
              >
                {{ formatDate(broadcast.created_at) }}
              </td>
              <td class="px-3 py-2.5" @click.stop>
                <div class="flex justify-end gap-1">
                  <Button
                    v-tooltip.top="t('BROADCAST.LIST.DUPLICATE')"
                    variant="ghost"
                    color="slate"
                    size="xs"
                    icon="i-lucide-copy"
                    @click="duplicateBroadcast(broadcast)"
                  />
                  <Button
                    v-tooltip.top="t('BROADCAST.LIST.DELETE')"
                    variant="ghost"
                    color="ruby"
                    size="xs"
                    icon="i-lucide-trash-2"
                    @click="removeBroadcast(broadcast)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Pagination -->
      <div
        v-if="filtered.length > PAGE_SIZES[0]"
        class="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 rounded-xl border border-n-weak bg-n-solid-1"
        data-testid="broadcast-pagination"
      >
        <span class="text-xs text-n-slate-11">
          {{
            t('BROADCAST.LIST.SHOWING', {
              start: pageData.start + 1,
              end: pageData.end,
              total: filtered.length,
            })
          }}
        </span>
        <div class="flex items-center gap-1">
          <Button
            variant="ghost"
            color="slate"
            size="xs"
            icon="i-lucide-chevron-left"
            :disabled="pageData.page === 1"
            @click="page = pageData.page - 1"
          />
          <button
            v-for="number in pages"
            :key="number"
            type="button"
            class="min-w-7 h-7 px-2 rounded-md text-xs tabular-nums"
            :class="
              number === pageData.page
                ? 'bg-n-brand/15 text-n-slate-12 font-semibold'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="page = number"
          >
            {{ number }}
          </button>
          <Button
            variant="ghost"
            color="slate"
            size="xs"
            icon="i-lucide-chevron-right"
            :disabled="pageData.page === pageData.totalPages"
            @click="page = pageData.page + 1"
          />
        </div>
        <label class="flex items-center gap-2 text-xs text-n-slate-11">
          {{ t('BROADCAST.LIST.PER_PAGE') }}
          <select
            v-model.number="pageSize"
            :class="controlClass"
            class="!w-20 h-7"
          >
            <option v-for="size in PAGE_SIZES" :key="size" :value="size">
              {{ size }}
            </option>
          </select>
        </label>
      </div>
    </div>
  </div>
</template>
