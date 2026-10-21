<script setup>
import { computed, nextTick, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import WorkspaceAPI from 'dashboard/api/workspace';
import ButtonNext from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import Logo from 'next/icon/Logo.vue';
import WorkspaceCover from 'next/workspace/WorkspaceCover.vue';
import WorkspaceAvatar from 'next/workspace/WorkspaceAvatar.vue';

defineProps({
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['showCreateAccountModal']);

// Past this many workspaces a search box earns its place.
const SEARCH_THRESHOLD = 5;

const { t } = useI18n();
const router = useRouter();
const { accountId, currentAccount } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const globalConfig = useMapGetter('globalConfig/get');
const userAccounts = useMapGetter('getUserAccounts');

const isOpen = ref(false);
const query = ref('');
const activeIndex = ref(0);
const unreadCounts = ref({});
const triggerRef = ref(null);
const searchRef = ref(null);
const listRef = ref(null);

const showAccountSwitcher = computed(
  () => userAccounts.value.length > 1 && currentAccount.value.name
);

const sortedAccounts = computed(() =>
  [...(currentUser.value.accounts || [])].sort((a, b) =>
    a.name.localeCompare(b.name)
  )
);

const showSearch = computed(
  () => sortedAccounts.value.length > SEARCH_THRESHOLD
);

const normalize = text =>
  (text || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

const filteredAccounts = computed(() => {
  const term = normalize(query.value.trim());
  if (!term) return sortedAccounts.value;
  return sortedAccounts.value.filter(account =>
    [account.name, account.vertical_name].some(text =>
      normalize(text).includes(term)
    )
  );
});

const currentMembership = computed(() =>
  sortedAccounts.value.find(account => account.id === accountId.value)
);
const isAdminHere = computed(
  () => currentMembership.value?.role === 'administrator'
);

const ROLE_LABELS = computed(() => ({
  administrator: t('WORKSPACE_SWITCHER.ROLES.ADMINISTRATOR'),
  agent: t('WORKSPACE_SWITCHER.ROLES.AGENT'),
}));

const roleLabel = account => {
  if (account.custom_role_id) return account.custom_role?.name;
  return ROLE_LABELS.value[account.role] || account.role;
};

const optionId = account => `workspace-option-${account.id}`;
const activeOption = computed(() => filteredAccounts.value[activeIndex.value]);

const fetchUnreadCounts = async () => {
  try {
    const { data } = await WorkspaceAPI.summaries();
    unreadCounts.value = Object.fromEntries(
      data.payload.map(row => [row.account_id, row.unread_notifications_count])
    );
  } catch {
    // The counters are a nicety; the switcher works without them.
  }
};

const scrollActiveIntoView = () => {
  nextTick(() => {
    const id = activeOption.value && optionId(activeOption.value);
    listRef.value
      ?.querySelector(`#${id}`)
      ?.scrollIntoView({ block: 'nearest' });
  });
};

const openPanel = async () => {
  isOpen.value = true;
  query.value = '';
  const currentIndex = sortedAccounts.value.findIndex(
    account => account.id === accountId.value
  );
  activeIndex.value = Math.max(currentIndex, 0);
  fetchUnreadCounts();
  await nextTick();
  (searchRef.value || listRef.value)?.focus();
  scrollActiveIntoView();
};

const closePanel = ({ restoreFocus = false } = {}) => {
  if (!isOpen.value) return;
  isOpen.value = false;
  if (restoreFocus) triggerRef.value?.focus();
};

const togglePanel = () => {
  if (isOpen.value) closePanel({ restoreFocus: true });
  else openPanel();
};

const switchTo = account => {
  if (!account) return;
  if (account.id === accountId.value) {
    closePanel({ restoreFocus: true });
    return;
  }
  window.location.href = `/app/accounts/${account.id}/dashboard`;
};

const moveActive = step => {
  const total = filteredAccounts.value.length;
  if (!total) return;
  activeIndex.value = (activeIndex.value + step + total) % total;
  scrollActiveIntoView();
};

const onPanelKeydown = event => {
  const { key } = event;
  if (key === 'ArrowDown' || key === 'ArrowUp') {
    event.preventDefault();
    moveActive(key === 'ArrowDown' ? 1 : -1);
  } else if (key === 'Home' || key === 'End') {
    event.preventDefault();
    activeIndex.value = key === 'Home' ? 0 : filteredAccounts.value.length - 1;
    scrollActiveIntoView();
  } else if (key === 'Enter') {
    event.preventDefault();
    switchTo(activeOption.value);
  } else if (key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    closePanel({ restoreFocus: true });
  } else if (/^[1-9]$/.test(key) && !query.value) {
    // Numbers jump straight to a workspace while the search is empty.
    event.preventDefault();
    switchTo(filteredAccounts.value[Number(key) - 1]);
  }
};

const onSearch = () => {
  activeIndex.value = 0;
};

const openCoverSettings = () => {
  closePanel();
  router.push({
    name: 'general_settings_index',
    params: { accountId: accountId.value },
  });
};

const emitNewAccount = () => {
  closePanel();
  emit('showCreateAccountModal');
};

useKeyboardEvents({
  '$mod+Shift+KeyK': {
    action: event => {
      if (!showAccountSwitcher.value) return;
      event.preventDefault();
      togglePanel();
    },
    allowOnFocusedInput: true,
  },
});
</script>

<template>
  <div v-on-click-outside="() => closePanel()" class="relative">
    <!-- Collapsed view: Logo trigger -->
    <button
      v-if="isCollapsed"
      ref="triggerRef"
      class="grid flex-shrink-0 place-content-center p-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
      :class="{ 'bg-n-alpha-1': isOpen }"
      :title="currentAccount.name"
      :aria-label="t('WORKSPACE_SWITCHER.OPEN')"
      aria-haspopup="listbox"
      :aria-expanded="isOpen"
      @click="togglePanel"
    >
      <Logo class="size-7" />
    </button>
    <!-- Expanded view: workspace avatar and name -->
    <button
      v-else
      id="sidebar-account-switcher"
      ref="triggerRef"
      :data-account-id="accountId"
      aria-haspopup="listbox"
      aria-controls="account-options"
      :aria-expanded="isOpen"
      class="flex items-center gap-2 justify-between w-full rounded-lg px-1 py-0.5 transition-colors"
      :class="[
        isOpen && 'bg-n-alpha-1',
        showAccountSwitcher
          ? 'hover:bg-n-alpha-1 cursor-pointer'
          : 'cursor-default',
      ]"
      @click="() => showAccountSwitcher && togglePanel()"
    >
      <span class="flex items-center gap-2 min-w-0">
        <WorkspaceAvatar
          v-if="currentMembership"
          :account="currentMembership"
          size="xs"
        />
        <span
          class="text-sm font-medium leading-5 text-n-slate-12 truncate"
          aria-live="polite"
        >
          {{ currentAccount.name }}
        </span>
      </span>

      <span
        v-if="showAccountSwitcher"
        aria-hidden="true"
        class="i-lucide-chevrons-up-down size-4 text-n-slate-10 flex-shrink-0"
      />
    </button>

    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 -translate-y-1 scale-[0.98]"
      leave-active-class="transition duration-150 ease-in"
      leave-to-class="opacity-0 -translate-y-1 scale-[0.98]"
    >
      <div
        v-if="isOpen && (showAccountSwitcher || isCollapsed)"
        class="absolute z-50 mt-2 top-full ltr:left-0 rtl:right-0 origin-top-left w-[26rem] max-w-[calc(100vw-1.5rem)] flex flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] shadow-xl"
        @keydown="onPanelKeydown"
      >
        <header class="flex items-center gap-3 px-4 pt-4 pb-3">
          <span
            class="grid flex-shrink-0 rounded-xl shadow-sm size-9 place-content-center bg-brand-gradient"
          >
            <Icon icon="i-lucide-layers" class="size-5 text-[#06131C]" />
          </span>
          <div class="min-w-0 flex-1">
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ t('WORKSPACE_SWITCHER.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11">
              {{
                t(
                  'WORKSPACE_SWITCHER.SUBTITLE',
                  { count: sortedAccounts.length },
                  sortedAccounts.length
                )
              }}
            </p>
          </div>
          <kbd
            class="hidden sm:inline-flex items-center gap-0.5 rounded-md border border-n-weak bg-n-alpha-1 px-1.5 py-0.5 font-sans text-xxs text-n-slate-11"
          >
            {{ t('WORKSPACE_SWITCHER.SHORTCUT') }}
          </kbd>
        </header>

        <div v-if="showSearch" class="px-4 pb-3">
          <label
            class="flex items-center gap-2 rounded-xl border border-n-weak bg-n-alpha-1 px-3 h-9 focus-within:border-n-brand"
          >
            <Icon
              icon="i-lucide-search"
              class="size-4 flex-shrink-0 text-n-slate-10"
            />
            <input
              ref="searchRef"
              v-model="query"
              type="search"
              role="combobox"
              aria-controls="account-options"
              :aria-expanded="true"
              :aria-activedescendant="
                activeOption ? optionId(activeOption) : undefined
              "
              :aria-label="t('WORKSPACE_SWITCHER.SEARCH')"
              :placeholder="t('WORKSPACE_SWITCHER.SEARCH')"
              class="flex-1 min-w-0 !m-0 !p-0 !h-auto !border-0 !bg-transparent !shadow-none text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:!ring-0"
              @input="onSearch"
            />
          </label>
        </div>

        <ul
          id="account-options"
          ref="listRef"
          role="listbox"
          tabindex="-1"
          :aria-label="t('WORKSPACE_SWITCHER.TITLE')"
          :aria-activedescendant="
            activeOption ? optionId(activeOption) : undefined
          "
          class="grid gap-2 px-3 pb-3 overflow-y-auto list-none m-0 max-h-[min(30rem,60vh)] outline-none"
        >
          <li
            v-for="(account, index) in filteredAccounts"
            :id="optionId(account)"
            :key="account.id"
            role="option"
            :aria-selected="index === activeIndex"
            :aria-current="account.id === accountId ? 'true' : undefined"
            class="group relative overflow-hidden rounded-xl border cursor-pointer bg-n-solid-1 transition duration-150 hover:-translate-y-px hover:shadow-md"
            :class="[
              index === activeIndex
                ? 'border-n-brand ring-2 ring-n-brand/30'
                : 'border-n-weak',
            ]"
            @click="switchTo(account)"
            @mousemove="activeIndex = index"
          >
            <WorkspaceCover :account="account" class="h-12">
              <span
                v-if="account.id === accountId"
                class="absolute top-2 ltr:left-2 rtl:right-2 inline-flex items-center gap-1 rounded-full bg-n-black/40 px-2 py-0.5 text-xxs font-medium text-white backdrop-blur"
              >
                <Icon icon="i-lucide-check" class="size-3" />
                {{ t('WORKSPACE_SWITCHER.CURRENT') }}
              </span>
              <kbd
                v-if="index < 9 && !query"
                class="absolute top-2 ltr:right-2 rtl:left-2 grid size-5 place-content-center rounded-md bg-n-black/40 font-sans text-xxs font-semibold text-white backdrop-blur"
              >
                {{ index + 1 }}
              </kbd>
            </WorkspaceCover>
            <div class="flex items-start gap-3 px-3 pb-3">
              <WorkspaceAvatar
                :account="account"
                class="-mt-5 ring-4 ring-n-solid-1 shadow-sm"
              />
              <div class="flex-1 min-w-0 pt-2">
                <p
                  class="text-sm font-semibold leading-5 text-n-slate-12 break-words line-clamp-2"
                  :title="account.name"
                >
                  {{ account.name }}
                </p>
                <div class="flex flex-wrap items-center gap-1.5 mt-1">
                  <span
                    class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xxs font-medium text-n-slate-11"
                  >
                    <Icon icon="i-lucide-shield" class="size-3" />
                    {{ roleLabel(account) }}
                  </span>
                  <span
                    v-if="account.vertical_name"
                    class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xxs font-medium text-n-slate-11"
                  >
                    <Icon icon="i-lucide-briefcase" class="size-3" />
                    {{ account.vertical_name }}
                  </span>
                </div>
              </div>
              <span
                v-if="unreadCounts[account.id]"
                class="mt-2 inline-flex flex-shrink-0 items-center gap-1 rounded-full bg-n-ruby-9 px-2 py-0.5 text-xxs font-semibold text-white"
                :title="
                  t(
                    'WORKSPACE_SWITCHER.UNREAD',
                    { count: unreadCounts[account.id] },
                    unreadCounts[account.id]
                  )
                "
              >
                <Icon icon="i-lucide-bell" class="size-3" />
                {{ unreadCounts[account.id] }}
              </span>
            </div>
          </li>
          <li
            v-if="!filteredAccounts.length"
            class="flex flex-col items-center gap-2 py-8 text-center"
          >
            <span
              class="grid size-10 place-content-center rounded-xl bg-brand-gradient-soft"
            >
              <Icon icon="i-lucide-search-x" class="size-5 text-n-slate-11" />
            </span>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('WORKSPACE_SWITCHER.EMPTY.TITLE') }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('WORKSPACE_SWITCHER.EMPTY.DESCRIPTION', { query }) }}
            </p>
          </li>
        </ul>

        <footer
          class="flex flex-wrap items-center gap-2 border-t border-n-weak px-4 py-3"
        >
          <p class="flex-1 min-w-0 text-xxs text-n-slate-10">
            {{ t('WORKSPACE_SWITCHER.HINT') }}
          </p>
          <button
            v-if="isAdminHere"
            type="button"
            class="inline-flex items-center gap-1.5 rounded-lg px-2.5 h-8 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
            @click="openCoverSettings"
          >
            <Icon icon="i-lucide-palette" class="size-4" />
            {{ t('WORKSPACE_SWITCHER.CUSTOMIZE') }}
          </button>
          <ButtonNext
            v-if="globalConfig.createNewAccountFromDashboard"
            size="sm"
            icon="i-lucide-plus"
            :label="t('CREATE_ACCOUNT.NEW_ACCOUNT')"
            @click="emitNewAccount"
          />
        </footer>
      </div>
    </Transition>
  </div>
</template>
