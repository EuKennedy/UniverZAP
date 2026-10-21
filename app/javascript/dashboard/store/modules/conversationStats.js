import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';

const state = {
  mineCount: 0,
  unAssignedCount: 0,
  allCount: 0,
  // UniverZAP: the Aguardando / Em atendimento views of the Todos dropdown
  waitingCount: 0,
  inAttendanceCount: 0,
  awaitingCustomerCount: 0,
  // UniverZAP groups tab
  groupCount: 0,
  statusCount: 0,
  teamCount: 0,
  // UniverZAP: "Resolvidas" in the Todos dropdown
  resolvedCount: 0,
};

export const getters = {
  getStats: $state => $state,
};

// Create a debounced version of the actual API call function
const fetchMetaData = async (commit, params) => {
  try {
    const response = await ConversationApi.meta(params);
    const {
      data: { meta },
    } = response;
    commit(types.SET_CONV_TAB_META, meta);
  } catch (error) {
    // ignore
  }
};

const debouncedFetchMetaData = debounce(fetchMetaData, 500, false, 1500);
const longDebouncedFetchMetaData = debounce(fetchMetaData, 5000, false, 10000);
const superLongDebouncedFetchMetaData = debounce(
  fetchMetaData,
  10000,
  false,
  20000
);

export const actions = {
  get: async ({ commit, state: $state }, params) => {
    if ($state.allCount > 5000) {
      superLongDebouncedFetchMetaData(commit, params);
    } else if ($state.allCount > 100) {
      longDebouncedFetchMetaData(commit, params);
    } else {
      debouncedFetchMetaData(commit, params);
    }
  },
  set({ commit }, meta) {
    commit(types.SET_CONV_TAB_META, meta);
  },
};

export const mutations = {
  [types.SET_CONV_TAB_META](
    $state,
    {
      mine_count: mineCount,
      unassigned_count: unAssignedCount,
      all_count: allCount,
      waiting_count: waitingCount,
      in_attendance_count: inAttendanceCount,
      awaiting_customer_count: awaitingCustomerCount,
      group_count: groupCount,
      status_count: statusCount,
      team_count: teamCount,
      resolved_count: resolvedCount,
    } = {}
  ) {
    $state.mineCount = mineCount;
    $state.allCount = allCount;
    $state.unAssignedCount = unAssignedCount;
    if (waitingCount !== undefined) $state.waitingCount = waitingCount;
    if (inAttendanceCount !== undefined)
      $state.inAttendanceCount = inAttendanceCount;
    if (awaitingCustomerCount !== undefined)
      $state.awaitingCustomerCount = awaitingCustomerCount;
    if (groupCount !== undefined) $state.groupCount = groupCount;
    if (statusCount !== undefined) $state.statusCount = statusCount;
    if (teamCount !== undefined) $state.teamCount = teamCount;
    if (resolvedCount !== undefined) $state.resolvedCount = resolvedCount;
    $state.updatedOn = new Date();
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
