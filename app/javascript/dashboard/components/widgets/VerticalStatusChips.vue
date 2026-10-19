<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useEmitter } from 'dashboard/composables/emitter';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useUISettings } from 'dashboard/composables/useUISettings';
import VerticalStatusesAPI from 'dashboard/api/verticalStatuses';

// UniverZAP: layer 2 of the conversation list — the labels that matter to
// whoever is looking, in order, each with how many OPEN conversations sit
// there. Three sources, most specific first: the agent's own pick ("só para
// mim", kept in their UI settings), the admin's pick for the whole team, the
// vertical's default stages. One scrollable line; a chip is a link to the
// label's own view, which already does everything else.
const route = useRoute();
const { isAdmin } = useAdmin();
const { uiSettings, updateUISettings } = useUISettings();

const PERSONAL_KEY = 'conversation_bar_labels_personal';
const personalTitles = computed(() => {
  const value = uiSettings.value[PERSONAL_KEY];
  return Array.isArray(value) ? value : null;
});

const statuses = ref([]);
const picking = ref(false);
const picked = ref([]);
const scope = ref('me');
const search = ref('');
const catalog = ref([]);
const saving = ref(false);

const REFRESH_MS = 30_000;
let fetchedAt = 0;
async function fetchStatuses(force = false) {
  if (!force && Date.now() - fetchedAt < REFRESH_MS) return;
  fetchedAt = Date.now();
  try {
    const { data } = personalTitles.value?.length
      ? await VerticalStatusesAPI.getFor(personalTitles.value)
      : await VerticalStatusesAPI.get();
    statuses.value = data.statuses;
  } catch (error) {
    // No vertical configured and nothing picked, or the request failed: the
    // row simply stays empty, the universal cards above are unaffected.
  }
}

const isActive = status =>
  route.name === 'label_conversations' && route.params.label === status.title;

async function openPicker() {
  picked.value = statuses.value.map(status => status.title);
  scope.value = 'me';
  search.value = '';
  picking.value = true;
  try {
    const { data } = await VerticalStatusesAPI.getCatalog();
    catalog.value = data.labels;
  } catch (error) {
    catalog.value = [];
  }
}

// Picked labels first, in bar order; then the rest by how much they are used.
const pickerRows = computed(() => {
  const term = search.value.trim().toLowerCase();
  const byTitle = Object.fromEntries(catalog.value.map(l => [l.title, l]));
  const chosen = picked.value
    .filter(title => byTitle[title])
    .map(title => byTitle[title]);
  const rest = catalog.value.filter(l => !picked.value.includes(l.title));
  return [...chosen, ...rest].filter(
    l => !term || l.title.toLowerCase().includes(term)
  );
});

function toggle(title) {
  picked.value = picked.value.includes(title)
    ? picked.value.filter(item => item !== title)
    : [...picked.value, title];
}

function move(title, delta) {
  const from = picked.value.indexOf(title);
  const to = from + delta;
  if (from < 0 || to < 0 || to >= picked.value.length) return;
  const next = [...picked.value];
  next.splice(from, 1);
  next.splice(to, 0, title);
  picked.value = next;
}

async function persist(titles) {
  if (scope.value === 'team') {
    await VerticalStatusesAPI.updateSelection(titles);
    // The team pick only shows when nothing personal is set.
    await updateUISettings({ [PERSONAL_KEY]: null });
  } else {
    await updateUISettings({ [PERSONAL_KEY]: titles });
  }
}

async function save(titles) {
  saving.value = true;
  try {
    await persist(titles);
    picking.value = false;
    await fetchStatuses(true);
  } finally {
    saving.value = false;
  }
}

// "×" on a chip: one click to take it off the bar you are looking at — the
// personal one when it exists, otherwise the team's (admins); an agent
// without a personal bar gets one.
async function removeChip(title) {
  scope.value = !personalTitles.value?.length && isAdmin.value ? 'team' : 'me';
  const titles = statuses.value
    .map(status => status.title)
    .filter(item => item !== title);
  await save(titles);
}

const canEdit = computed(() => true);

onMounted(() => fetchStatuses(true));
// Same signal that refreshes the counters above, so the stages stay live.
useEmitter('fetch_conversation_stats', () => fetchStatuses());
</script>

<template>
  <div
    v-if="statuses.length || canEdit"
    class="relative border-b border-n-weak"
  >
    <ul
      class="flex items-center gap-1.5 px-3 pt-1.5 pb-2 mb-0 list-none overflow-x-auto [scrollbar-width:none]"
    >
      <li
        v-for="status in statuses"
        :key="status.title"
        class="shrink-0 group relative"
      >
        <router-link
          v-slot="{ href, navigate }"
          :to="{ name: 'label_conversations', params: { label: status.title } }"
          custom
        >
          <a
            :href="href"
            :title="status.description"
            class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full whitespace-nowrap"
            :class="
              isActive(status)
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="navigate"
          >
            <span
              class="rounded-full size-1.5"
              :style="{ backgroundColor: status.color }"
            />
            {{ status.title }}
            <span
              class="tabular-nums"
              :class="
                status.count ? 'text-n-slate-12 font-medium' : 'text-n-slate-9'
              "
            >
              {{ status.count }}
            </span>
          </a>
        </router-link>
        <button
          type="button"
          class="absolute -top-1 -right-1 hidden group-hover:flex items-center justify-center rounded-full size-4 bg-n-solid-3 text-n-slate-11 hover:text-n-ruby-11"
          :title="$t('CHAT_LIST.STATUS_BAR.REMOVE')"
          @click.prevent="removeChip(status.title)"
        >
          <span class="i-lucide-x size-3" />
        </button>
      </li>
      <li class="shrink-0 ml-auto">
        <button
          type="button"
          class="flex items-center justify-center rounded-full size-6 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="$t('CHAT_LIST.STATUS_BAR.PICK')"
          @click="picking ? (picking = false) : openPicker()"
        >
          <span class="i-lucide-settings-2 size-3.5" />
        </button>
      </li>
    </ul>

    <div
      v-if="picking"
      class="absolute right-2 top-full z-30 w-80 p-3 mt-1 rounded-xl border border-n-weak bg-n-solid-2 shadow-lg"
    >
      <p class="mb-2 text-xs font-medium text-n-slate-12">
        {{ $t('CHAT_LIST.STATUS_BAR.PICK') }}
      </p>
      <div class="flex items-center gap-1 mb-2 text-xs">
        <button
          type="button"
          class="px-2 py-0.5 rounded-md"
          :class="
            scope === 'me'
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-1 text-n-slate-11'
          "
          @click="scope = 'me'"
        >
          {{ $t('CHAT_LIST.STATUS_BAR.SCOPE_ME') }}
        </button>
        <button
          v-if="isAdmin"
          type="button"
          class="px-2 py-0.5 rounded-md"
          :class="
            scope === 'team'
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-1 text-n-slate-11'
          "
          @click="scope = 'team'"
        >
          {{ $t('CHAT_LIST.STATUS_BAR.SCOPE_TEAM') }}
        </button>
      </div>
      <input
        v-model="search"
        type="search"
        class="!mb-2 !h-8 !text-xs"
        :placeholder="$t('CHAT_LIST.STATUS_BAR.SEARCH')"
      />
      <ul class="mb-3 overflow-y-auto list-none max-h-64">
        <li
          v-for="label in pickerRows"
          :key="label.title"
          class="flex items-center gap-2 px-1 py-1 text-xs rounded text-n-slate-12 hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            class="!m-0"
            :checked="picked.includes(label.title)"
            @change="toggle(label.title)"
          />
          <span
            class="rounded-full size-1.5"
            :style="{ backgroundColor: label.color }"
          />
          <span class="truncate" :title="label.description">
            {{ label.title }}
          </span>
          <span class="ml-auto text-n-slate-10 tabular-nums whitespace-nowrap">
            {{ $t('CHAT_LIST.STATUS_BAR.OPEN', { n: label.count }) }}
          </span>
          <template v-if="picked.includes(label.title)">
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-slate-12 disabled:opacity-30"
              :disabled="picked.indexOf(label.title) === 0"
              :title="$t('CHAT_LIST.STATUS_BAR.UP')"
              @click="move(label.title, -1)"
            >
              <span class="i-lucide-chevron-up size-3.5" />
            </button>
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-slate-12 disabled:opacity-30"
              :disabled="picked.indexOf(label.title) === picked.length - 1"
              :title="$t('CHAT_LIST.STATUS_BAR.DOWN')"
              @click="move(label.title, 1)"
            >
              <span class="i-lucide-chevron-down size-3.5" />
            </button>
          </template>
        </li>
      </ul>
      <div class="flex items-center justify-between gap-2">
        <button
          type="button"
          class="text-xs text-n-slate-11 hover:text-n-slate-12"
          :disabled="saving"
          @click="save([])"
        >
          {{
            scope === 'team'
              ? $t('CHAT_LIST.STATUS_BAR.RESET')
              : $t('CHAT_LIST.STATUS_BAR.RESET_ME')
          }}
        </button>
        <button
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-60"
          :disabled="saving"
          @click="save(picked)"
        >
          {{ $t('CHAT_LIST.STATUS_BAR.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
