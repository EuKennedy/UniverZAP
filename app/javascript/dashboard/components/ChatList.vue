<script setup>
import { ref, unref, provide, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import ChatListHeader from './ChatListHeader.vue';
import ConversationList from './ConversationList.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import VerticalStatusChips from './widgets/VerticalStatusChips.vue';
import ConversationKpiRow from './widgets/ConversationKpiRow.vue';
import ConversationDateStrip from './widgets/ConversationDateStrip.vue';
import TeamMembersBar from './widgets/TeamMembersBar.vue';
import { isOurTurn } from 'dashboard/helper/conversationTurn';
import ReportsAPI from 'dashboard/api/reports';
import ConversationListFilter from 'dashboard/components-next/filter/ConversationListFilter.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { conversationListPageURL } from '../helper/URLHelper';
import {
  buildListFilterConditions,
  describeListFilter,
  emptyListFilter,
  listFilterCondition,
} from '../helper/conversationListFilter';
import {
  isOnMentionsView,
  isOnParticipatingView,
  isOnUnattendedView,
} from '../store/modules/conversations/helpers/actionHelpers';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showConversationList: { default: true, type: Boolean },
  isOnExpandedLayout: { default: false, type: Boolean },
});

const emit = defineEmits(['conversationLoad']);
const { uiSettings, updateUISettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();

const resolveAttributesModalRef = ref(null);

const activeAssigneeTab = ref(wootConstants.ASSIGNEE_TYPE.ALL);
const activeListView = ref(wootConstants.LIST_VIEW.ALL);
const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const todayCollapsed = ref(false);
function toggleToday() {
  todayCollapsed.value = !todayCollapsed.value;
  updateUISettings({ conversation_list_today_collapsed: todayCollapsed.value });
}

// UniverZAP: the agenda — the day the conversations on screen started on
// ('YYYY-MM-DD', agent's timezone; null = every day). Not remembered: a
// reload always opens on the whole queue. The open/folded week is.
const createdOn = ref(null);
const datesExpanded = ref(false);
function toggleDates() {
  datesExpanded.value = !datesExpanded.value;
  updateUISettings({ conversation_list_dates_open: datesExpanded.value });
}
const showAdvancedFilters = ref(false);
const listFilter = ref(emptyListFilter());
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const appliedFilter = ref([]);
const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const allChatList = useMapGetter('getAllStatusChats');
const participatingChatsList = useMapGetter('getParticipatingChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
const currentAccountId = useMapGetter('getCurrentAccountId');
// The account record (accounts/getAccount), which carries vertical_profile;
// getCurrentAccount is the profile's slimmer copy without it.
const { currentAccount } = useAccount();
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');
const getConversationById = useMapGetter('getConversationById');

const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
} = useBulkActions();

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const { checkMissingAttributes } = useConversationRequiredAttributes();

// computed

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value;
  return { id, name };
});

const userPermissions = computed(() => {
  return getUserPermissions(currentUser.value, currentAccountId.value);
});

const VIEW_COUNT_KEYS = {
  [wootConstants.LIST_VIEW.ALL]: 'allCount',
  [wootConstants.LIST_VIEW.ME]: 'mineCount',
  [wootConstants.LIST_VIEW.WAITING]: 'waitingCount',
  [wootConstants.LIST_VIEW.AWAITING_CUSTOMER]: 'awaitingCustomerCount',
  [wootConstants.LIST_VIEW.IN_ATTENDANCE]: 'inAttendanceCount',
  // UniverZAP: "Fila, sem dono" and "Resolvidas" quick filters
  [wootConstants.LIST_VIEW.UNASSIGNED]: 'unAssignedCount',
  [wootConstants.LIST_VIEW.RESOLVED]: 'resolvedCount',
  // UniverZAP: "Agendadas" — resolved as customer won (Resolver > Agendado),
  // kept apart from the plain Resolvidas. Only for verticals that schedule.
  [wootConstants.LIST_VIEW.SCHEDULED]: 'scheduledCount',
};

const scheduleStatus = computed(
  () => currentAccount.value?.vertical_profile?.schedule_status || null
);

// Shown as KPI cards below the Todos/Grupos tabs, in addition to living in
// the Todos dropdown — same state, just the day's triage at a glance instead
// of a click deep. Todos and Minhas stay dropdown-only: the tab already shows
// Todos' count, and for a reception Minhas is usually the same number.
const KPI_VIEWS = [
  wootConstants.LIST_VIEW.WAITING,
  wootConstants.LIST_VIEW.AWAITING_CUSTOMER,
  wootConstants.LIST_VIEW.UNASSIGNED,
  wootConstants.LIST_VIEW.RESOLVED,
  wootConstants.LIST_VIEW.SCHEDULED,
];

const viewItems = computed(() =>
  Object.entries(VIEW_COUNT_KEYS)
    .filter(
      ([key]) =>
        key !== wootConstants.LIST_VIEW.SCHEDULED || scheduleStatus.value
    )
    .map(([key, countKey]) => ({
      key,
      name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
      count: conversationStats.value[countKey] || 0,
    }))
);

const kpiItems = computed(() =>
  viewItems.value.filter(item => KPI_VIEWS.includes(item.key))
);

const assigneeTabItems = computed(() => {
  return filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  ).map(({ key, count: countKey }) => ({
    key,
    name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
    count: conversationStats.value[countKey] || 0,
    ...(key === wootConstants.ASSIGNEE_TYPE.ALL && {
      options: viewItems.value,
      activeOption: activeListView.value,
    }),
  }));
});

const isGroupsTab = computed(
  () => activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.GROUPS
);
const isStatusTab = computed(
  () => activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.STATUS
);
const isTeamTab = computed(
  () => activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.TEAM
);
// Grupos and Status are tabs of their own kind of chat, outside the Todos
// views (dropdown, KPI cards, label bar).
const isSegmentTab = computed(
  () => isGroupsTab.value || isStatusTab.value || isTeamTab.value
);

// The bucket on screen: Grupos, or Todos narrowed by its dropdown. Pagination
// and the end-of-list badge are kept per bucket.
const listKey = computed(() =>
  isSegmentTab.value ? activeAssigneeTab.value : activeListView.value
);

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL
  );
});

const currentPageFilterKey = computed(() => {
  return hasAppliedFiltersOrActiveFolders.value
    ? 'appliedFilters'
    : listKey.value;
});

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  listKey
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);

const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

const activeAssigneeTabCount = computed(() => {
  const segmentCountKeys = {
    groups: 'groupCount',
    status: 'statusCount',
    team: 'teamCount',
  };
  const countKey = isSegmentTab.value
    ? segmentCountKeys[activeAssigneeTab.value]
    : VIEW_COUNT_KEYS[activeListView.value];
  return conversationStats.value[countKey] || 0;
});

const conversationListPagination = computed(() => {
  // Must match the backend CONVERSATION_RESULTS_PER_PAGE (env). Loads 50
  // conversations per scroll/load, appended incrementally.
  const conversationsPerPage = 50;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < conversationsPerPage &&
    activeAssigneeTabCount.value < conversationsPerPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
    return 1;
  }

  return currentPage.value + 1;
});

// The two halves of Em atendimento, by whose turn it is.
const TURN_VIEWS = [
  wootConstants.LIST_VIEW.WAITING,
  wootConstants.LIST_VIEW.AWAITING_CUSTOMER,
];

// The two halves of the resolved list, by whether the customer was won.
const RESOLVED_VIEWS = [
  wootConstants.LIST_VIEW.RESOLVED,
  wootConstants.LIST_VIEW.SCHEDULED,
];

// Views that travel as `attendance_state` so the backend narrows the list
// (and the agenda strip) the same way the client does below.
const ATTENDANCE_VIEWS = [
  wootConstants.LIST_VIEW.WAITING,
  wootConstants.LIST_VIEW.AWAITING_CUSTOMER,
  wootConstants.LIST_VIEW.IN_ATTENDANCE,
  ...RESOLVED_VIEWS,
];

const isMineView = computed(
  () =>
    !isSegmentTab.value && activeListView.value === wootConstants.LIST_VIEW.ME
);

const isUnassignedView = computed(
  () =>
    !isSegmentTab.value &&
    activeListView.value === wootConstants.LIST_VIEW.UNASSIGNED
);

function resolveAssigneeType() {
  if (isMineView.value) return wootConstants.ASSIGNEE_TYPE.ME;
  if (isUnassignedView.value) return wootConstants.ASSIGNEE_TYPE.UNASSIGNED;
  return wootConstants.ASSIGNEE_TYPE.ALL;
}

// UniverZAP: Grupos is not an assignee filter but a `conversation_type`.
// Minhas / Fila (sem dono) are assignee_type; Aguardando / Em atendimento
// travel as `attendance_state`, so they narrow the route's own
// conversation_type.
const conversationFilters = computed(() => {
  return {
    inboxId: props.conversationInbox ? props.conversationInbox : undefined,
    assigneeType: resolveAssigneeType(),
    status: activeStatus.value,
    sortBy: activeSortBy.value,
    page: conversationListPagination.value,
    labels: props.label ? [props.label] : undefined,
    teamId: props.teamId || undefined,
    conversationType: isSegmentTab.value
      ? activeAssigneeTab.value
      : props.conversationType || undefined,
    attendanceState:
      !isSegmentTab.value && ATTENDANCE_VIEWS.includes(activeListView.value)
        ? activeListView.value
        : undefined,
    createdOn: createdOn.value || undefined,
    // The bucket this page belongs to, so the store files pagination under
    // the same key this list reads it from.
    listKey: listKey.value,
  };
});

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const pageTitle = computed(() => {
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }
  if (inbox.value.name) {
    return inbox.value.name;
  }
  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }
  if (props.label) {
    return `#${props.label}`;
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.MENTION) {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (
    props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
  ) {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.UNATTENDED) {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }
  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }
  return t('CHAT_LIST.TAB_HEADING');
});

const localDayKey = seconds => {
  const date = new Date(seconds * 1000);
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};

// What the agenda counts: the view on screen, without paging or sorting.
const dateScope = computed(() => {
  const filters = conversationFilters.value;
  return {
    inboxId: filters.inboxId,
    assigneeType: filters.assigneeType,
    status: filters.status,
    labels: filters.labels,
    teamId: filters.teamId,
    conversationType: filters.conversationType,
    attendanceState: filters.attendanceState,
  };
});

// Customer won: carries the vertical's scheduling status. Without one the
// account has no Agendadas and every resolved conversation is a plain one.
const isScheduled = c =>
  !!scheduleStatus.value && (c.labels || []).includes(scheduleStatus.value);

// The store accumulates every bucket fetched so far, so the list on screen is
// the client-side mirror of the backend split: Grupos holds ONLY WhatsApp
// groups, Todos everything else, narrowed by the view of its dropdown.
function filterByListKey(conversations) {
  if (isGroupsTab.value) {
    return conversations.filter(c => c.is_group);
  }
  if (isStatusTab.value) {
    return conversations.filter(c => c.is_status_broadcast);
  }
  if (isTeamTab.value) {
    return conversations.filter(c => c.is_team);
  }
  const nonGroups = conversations.filter(
    c => !c.is_group && !c.is_status_broadcast && !c.is_team
  );
  switch (activeListView.value) {
    case wootConstants.LIST_VIEW.ME:
      return nonGroups.filter(
        c => c.meta?.assignee?.id === currentUser.value?.id
      );
    case wootConstants.LIST_VIEW.WAITING:
      return nonGroups.filter(isOurTurn);
    case wootConstants.LIST_VIEW.AWAITING_CUSTOMER:
      return nonGroups.filter(c => !isOurTurn(c));
    case wootConstants.LIST_VIEW.UNASSIGNED:
      return nonGroups.filter(c => !c.meta?.assignee);
    case wootConstants.LIST_VIEW.RESOLVED:
      return nonGroups.filter(c => c.status === 'resolved' && !isScheduled(c));
    case wootConstants.LIST_VIEW.SCHEDULED:
      return nonGroups.filter(c => c.status === 'resolved' && isScheduled(c));
    default:
      return nonGroups;
  }
}

const conversationList = computed(() => {
  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;
    const chats =
      props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
        ? participatingChatsList.value(filters)
        : allChatList.value(filters);
    localConversationList = filterByListKey(chats);
    // A conversation that starts while a past day is on screen arrives by
    // websocket into the same store; keep it out of that day.
    if (createdOn.value) {
      localConversationList = localConversationList.filter(
        c => localDayKey(c.created_at) === createdOn.value
      );
    }
  } else {
    localConversationList = [...chatLists.value];
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  return localConversationList;
});

// Stop paginating once we already hold everything the tab badge promises.
// `buildConversationList` only marks the list "end reached" when a page comes
// back empty, so on short tabs (e.g. Grupos with a single conversation) the
// IntersectionObserver could keep firing loadMore → refetch in a loop and
// hammer the server. Comparing the loaded count against the backend-computed
// badge count gives us a hard, request-free stop.
const hasLoadedAllForTab = computed(
  () =>
    !hasAppliedFiltersOrActiveFolders.value &&
    activeAssigneeTabCount.value > 0 &&
    conversationList.value.length >= activeAssigneeTabCount.value
);

const showEndOfListMessage = computed(() => {
  return !!(
    conversationList.value.length &&
    (hasCurrentPageEndReached.value || hasLoadedAllForTab.value) &&
    !chatListLoading.value
  );
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

// ---------------------- Methods -----------------------
function setFiltersFromUISettings() {
  const {
    conversations_filter_by: filterBy = {},
    conversation_list_view: view,
    conversation_list_today_collapsed: todayPref,
  } = uiSettings.value;
  // The "Hoje" block opens on a desktop and starts folded on a phone, where
  // every row of the list counts; once the agent toggles it, their choice
  // wins on every device.
  todayCollapsed.value =
    typeof todayPref === 'boolean'
      ? todayPref
      : window.matchMedia('(max-width: 767px)').matches;
  datesExpanded.value = !!uiSettings.value.conversation_list_dates_open;
  const { status, order_by: orderBy } = filterBy;
  activeListView.value = Object.values(wootConstants.LIST_VIEW).includes(view)
    ? view
    : wootConstants.LIST_VIEW.ALL;
  // Resolvidas is backed by status, not by the persisted status filter: a
  // restored Resolvidas view with status "open" would list nothing and spin.
  activeStatus.value = RESOLVED_VIEWS.includes(activeListView.value)
    ? wootConstants.STATUS_TYPE.RESOLVED
    : status || wootConstants.STATUS_TYPE.OPEN;
  // The view persists across reloads via conversation_list_view, but an
  // explicit order_by (picked from the sort filter) doesn't carry the
  // Aguardando-is-the-fila-de-risco default with it — without this, reopening
  // the app on a restored Aguardando view silently falls back to last
  // activity instead of longest wait first.
  const defaultSortBy =
    activeListView.value === wootConstants.LIST_VIEW.WAITING
      ? wootConstants.SORT_BY_TYPE.WAITING_SINCE_ASC
      : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(
    orderBy
  )
    ? orderBy
    : defaultSortBy;
}

function emitConversationLoaded() {
  emit('conversationLoad');
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
    })
    .then(emitConversationLoaded);

  showAdvancedFilters.value = false;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
    })
    .then(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  resetBulkActions();
  foldersQuery.value = filterQueryGenerator(payload);
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  fetchFilteredConversations(payload);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);
  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };
  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  // Here we are setting the params for edit folder modal to show the existing values.

  // For agent, team, inboxes,and campaigns we get only the id's from the query.
  // So we are mapping the id's to the actual values.

  // For labels we get the name of the label from the query.
  // If we delete the label from the label list then we will not be able to show the label name.

  // For custom attributes we get only attribute key.
  // So we are mapping it to find the input type of the attribute to show in the edit folder modal.
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    languages: languages,
    countries: countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    activeAssigneeTab.value
  );
  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  // Here we are setting the params for edit folder modal.
  //  To show the existing values. when we click on edit folder button.

  // Here we get the query from the active folder.
  // And we are mapping the query to the actual values.
  // To show in the edit folder modal by the help of generateValuesForEditCustomViews helper.
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }
  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }
  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations() {
  store.dispatch('updateChatListFilters', conversationFilters.value);
  store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

function resetAndFetchData() {
  appliedFilter.value = [];
  listFilter.value = emptyListFilter();
  resetBulkActions();
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  store.dispatch('clearConversationFilters');
  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  }
  if (props.foldersId) {
    return;
  }
  fetchConversations();
}

// Someone joined or left the team: their chats changed tab, so refetch the
// list and the badges.
function onTeamChanged() {
  resetAndFetchData();
  store.dispatch('conversationStats/get', conversationFilters.value);
}

// A different day is a different list: start over from its first page.
function setCreatedOn(day) {
  createdOn.value = day;
  resetAndFetchData();
}

// UniverZAP: the list filter narrows what the list was showing — the status,
// the tab (Todos or Grupos, and the Todos dropdown) and the inbox, team or
// label of the route — so those travel as conditions of their own.
function listContextConditions() {
  const conditions = [
    listFilterCondition('status', 'equal_to', [activeStatus.value]),
    listFilterCondition('is_group', 'equal_to', [isGroupsTab.value]),
  ];
  if (isMineView.value) {
    conditions.push(
      listFilterCondition('assignee_id', 'equal_to', [currentUser.value.id])
    );
  }
  if (!isSegmentTab.value && TURN_VIEWS.includes(activeListView.value)) {
    conditions.push(
      listFilterCondition('awaiting_reply', 'equal_to', [
        activeListView.value === wootConstants.LIST_VIEW.WAITING,
      ])
    );
  }
  if (props.conversationInbox) {
    conditions.push(
      listFilterCondition('inbox_id', 'equal_to', [
        Number(props.conversationInbox),
      ])
    );
  }
  if (props.teamId) {
    conditions.push(
      listFilterCondition('team_id', 'equal_to', [Number(props.teamId)])
    );
  }
  if (props.label) {
    conditions.push(listFilterCondition('labels', 'equal_to', [props.label]));
  }
  return conditions;
}

function applyListFilter(filter) {
  const fieldConditions = buildListFilterConditions(filter);
  if (!fieldConditions.length) {
    resetAndFetchData();
    return;
  }
  const conditions = [...listContextConditions(), ...fieldConditions];
  store.dispatch('setConversationFilters', conditions);
  onApplyFilter(conditions);
  listFilter.value = filter;
}

const listFilterChips = computed(() => describeListFilter(listFilter.value, t));

// The bucket the applied filter narrows, shown as its first chip.
const listFilterScope = computed(() => {
  if (isGroupsTab.value) return t('CHAT_LIST.ASSIGNEE_TYPE_TABS.groups');
  if (isStatusTab.value) return t('CHAT_LIST.ASSIGNEE_TYPE_TABS.status');
  if (isTeamTab.value) return t('CHAT_LIST.ASSIGNEE_TYPE_TABS.team');
  return t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${activeListView.value}`);
});

const hasAppliedListFilter = computed(
  () => hasAppliedFilters.value && !hasActiveFolders.value
);

function loadMoreConversations() {
  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    return;
  }

  // Hard stop: never refetch once we already hold the whole tab. Prevents the
  // loadMore/refetch loop on short tabs (Grupos) from spamming the backend.
  if (hasLoadedAllForTab.value) {
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

// Switching buckets keeps what the store already holds; only a bucket that was
// never fetched asks the server for its first page.
function fetchIfBucketIsEmpty() {
  resetBulkActions();
  emitter.emit('clearSearchInput');
  if (!currentPage.value) {
    fetchConversations();
  }
}

function updateAssigneeTab(selectedTab) {
  if (activeAssigneeTab.value !== selectedTab) {
    activeAssigneeTab.value = selectedTab;
    fetchIfBucketIsEmpty();
  }
}

// The dropdown belongs to Todos: picking a view from it also leaves Grupos.
// The agent's last view is kept, so the list opens where they left it.
function updateView(selectedView) {
  if (activeListView.value === selectedView && !isSegmentTab.value) return;
  // Resolvidas is the one view backed by conversation status rather than
  // assignee/attendance, so entering or leaving it is the only time this
  // flips activeStatus — every other transition leaves it untouched.
  if (RESOLVED_VIEWS.includes(selectedView)) {
    activeStatus.value = wootConstants.STATUS_TYPE.RESOLVED;
  } else if (RESOLVED_VIEWS.includes(activeListView.value)) {
    activeStatus.value = wootConstants.STATUS_TYPE.OPEN;
  }
  // Aguardando is the fila de risco: it only earns that name sorted oldest
  // wait first, so picking it also picks that sort — same enter/exit
  // symmetry as Resolvidas above, so leaving it doesn't strand every other
  // view sorted by wait time.
  if (selectedView === wootConstants.LIST_VIEW.WAITING) {
    activeSortBy.value = wootConstants.SORT_BY_TYPE.WAITING_SINCE_ASC;
  } else if (activeListView.value === wootConstants.LIST_VIEW.WAITING) {
    activeSortBy.value = wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
  }
  activeListView.value = selectedView;
  activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ALL;
  updateUISettings({ conversation_list_view: selectedView });
  fetchIfBucketIsEmpty();
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    activeStatus.value = value;
  } else {
    activeSortBy.value = value;
  }
  resetAndFetchData();
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;
  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList() {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.MENTION;
  } else if (isOnParticipatingView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.PARTICIPATING;
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.UNATTENDED;
  }
  router.push(
    conversationListPageURL({
      accountId,
      conversationType: conversationType,
      customViewId: props.foldersId,
      inboxId,
      label,
      teamId,
    })
  );
}

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });
  store.dispatch('assignPriority', { conversationId, priority }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });
    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch (error) {
    // Ignore error
  }
}
async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch (error) {
    // Ignore error
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(
  conversationId,
  status,
  snoozedUntil,
  customAttributes = null
) {
  const payload = {
    conversationId,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
}

function handleResolveConversation(conversationId, status, snoozedUntil) {
  if (status !== wootConstants.STATUS_TYPE.RESOLVED) {
    toggleConversationStatus(conversationId, status, snoozedUntil);
    return;
  }

  // Check for required attributes before resolving
  const conversation = getConversationById.value(conversationId);
  const currentCustomAttributes = conversation?.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    // Pass conversation context through the modal's API
    const conversationContext = {
      id: conversationId,
      snoozedUntil,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleConversationStatus(conversationId, status, snoozedUntil);
  }
}

function handleResolveWithAttributes({ attributes, context }) {
  if (context) {
    const existingConversation = getConversationById.value(context.id);
    const currentCustomAttributes =
      existingConversation?.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };

    toggleConversationStatus(
      context.id,
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return getConversationById.value(item)?.status === status;
  });
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

// Median time to the first reply for today's conversations, read from the
// same endpoint the Painel uses so the bar never tells a different story.
// Reports are admin-only, so for an agent the request fails and the line
// simply stays hidden. Refreshed with the stats, but at most once a minute:
// the dashboard payload is far heavier than the counters.
const FIRST_REPLY_REFRESH_MS = 60_000;
const firstReply = ref();
let firstReplyFetchedAt = 0;
async function fetchFirstReplyTime() {
  if (Date.now() - firstReplyFetchedAt < FIRST_REPLY_REFRESH_MS) return;
  firstReplyFetchedAt = Date.now();
  try {
    const from = Math.floor(new Date().setHours(0, 0, 0, 0) / 1000);
    const to = Math.floor(Date.now() / 1000);
    const { data } = await ReportsAPI.getDashboard({ from, to });
    const {
      median_first_response_seconds: median,
      replied,
      created,
    } = data.queue;
    firstReply.value = { median, replied, created };
  } catch {
    firstReply.value = undefined;
  }
}

useEmitter('fetch_conversation_stats', () => {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  store.dispatch('conversationStats/get', conversationFilters.value);
  fetchFirstReplyTime();
});

onMounted(() => {
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  fetchFirstReplyTime();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }
});

const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch (error) {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeLabels', onRemoveLabels);
provide('updateConversationStatus', handleResolveConversation);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

watch(activeTeam, () => resetAndFetchData());
// The list getter re-sorts the fetched page client-side with the store's
// chatSortFilter, so a sort the view picked for itself (Aguardando's
// longest-wait-first) has to reach the store too — otherwise the server
// returns the fila de risco in order and the page renders it by last
// activity. The manual sort dropdown already dispatches this itself.
watch(activeSortBy, sortBy => store.dispatch('setChatSortFilter', sortBy));

watch(
  computed(() => props.conversationInbox),
  () => resetAndFetchData()
);
watch(
  computed(() => props.label),
  () => resetAndFetchData()
);
watch(
  computed(() => props.conversationType),
  () => resetAndFetchData()
);

watch(activeFolder, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('customViews/setActiveConversationFolder', newVal || null);
  }
  resetAndFetchData();
});

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

watch(conversationFilters, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('updateChatListFilters', newVal);
  }
});
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 conversations-list-wrap bg-n-surface-1 relative"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : 'w-[340px] 2xl:w-[412px]',
    ]"
  >
    <slot />
    <ChatListHeader
      :page-title="pageTitle"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="chatListLoading && !conversationList.length"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="resetAndFetchData"
      @basic-filter-change="onBasicFilterChange"
    />

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <ChatTypeTabs
      v-if="!hasAppliedFiltersOrActiveFolders"
      :items="assigneeTabItems"
      :active-tab="activeAssigneeTab"
      @chat-tab-change="updateAssigneeTab"
      @option-change="updateView"
    >
      <ConversationListFilter :filter="listFilter" @apply="applyListFilter" />
    </ChatTypeTabs>
    <ConversationKpiRow
      v-if="!hasAppliedFiltersOrActiveFolders && !isSegmentTab"
      :items="kpiItems"
      :active-key="activeListView"
      :first-reply="firstReply"
      :collapsed="todayCollapsed"
      @select="updateView"
      @toggle="toggleToday"
    />
    <VerticalStatusChips
      v-if="!hasAppliedFiltersOrActiveFolders && !isSegmentTab"
    />
    <div
      v-else-if="hasAppliedListFilter"
      class="flex items-center w-full h-10 gap-2 px-3 -mt-1 border-b border-n-weak"
    >
      <ul
        class="flex items-center flex-1 min-w-0 gap-1.5 mb-0 overflow-x-auto list-none [scrollbar-width:none]"
      >
        <li
          class="px-2 py-0.5 text-xs rounded-md shrink-0 bg-n-alpha-1 text-n-slate-11"
        >
          {{ listFilterScope }}
        </li>
        <li
          v-for="(chip, index) in listFilterChips"
          :key="index"
          class="px-2 py-0.5 text-xs rounded-md shrink-0 bg-n-teal-3 text-n-teal-11"
        >
          {{ chip }}
        </li>
      </ul>
      <ConversationListFilter :filter="listFilter" @apply="applyListFilter" />
    </div>
    <TeamMembersBar
      v-if="isTeamTab && !hasAppliedFiltersOrActiveFolders"
      @changed="onTeamChanged"
    />
    <ConversationDateStrip
      v-if="!hasAppliedFiltersOrActiveFolders"
      :model-value="createdOn"
      :scope="dateScope"
      :expanded="datesExpanded"
      @update:model-value="setCreatedOn"
      @toggle="toggleDates"
    />

    <p
      v-if="!chatListLoading && !conversationList.length"
      class="flex overflow-auto justify-center items-center p-4"
    >
      {{ $t('CHAT_LIST.LIST.404') }}
    </p>
    <ConversationBulkActions
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      :class="isOnExpandedLayout && 'sm:!w-[24rem] !w-full'"
      @select-all-conversations="toggleSelectAll"
    />
    <ConversationList
      :conversation-list="conversationList"
      :is-loading="chatListLoading"
      :show-end-of-list-message="showEndOfListMessage"
      :label="label"
      :team-id="teamId"
      :folders-id="foldersId"
      :conversation-type="conversationType"
      :show-assignee="showAssigneeInConversationCard"
      :is-on-expanded-layout="isOnExpandedLayout"
      @load-more="loadMoreConversations"
    />
    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />
    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>
