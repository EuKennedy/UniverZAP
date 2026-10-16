import * as types from '../mutation-types';

// Keyed by the bucket on screen (ChatList's listKey): Todos and its dropdown
// states, Grupos, or the applied advanced filters.
const state = {
  currentPage: {
    all: 0,
    unanswered: 0,
    answered: 0,
    groups: 0,
    appliedFilters: 0,
  },
  hasEndReached: {
    all: false,
    unanswered: false,
    answered: false,
    groups: false,
  },
};

export const getters = {
  getHasEndReached: $state => filter => {
    return $state.hasEndReached[filter];
  },
  // Zero for a tab this state was never told about. The fork once added tabs
  // (Aguardando, Em atendimento, Grupos) without keys here, so the page came
  // back undefined, `currentPage + 1` was
  // NaN, and every request asked the server for page NaN — which answers with
  // page 1, for ever. The list never grew past the first page, so neither
  // hasLoadedAllForTab nor the empty-page end marker could ever fire, and the
  // IntersectionObserver refired loadMore without end: one open tab hammering
  // the backend in a loop. A default here covers every tab, including the next
  // one somebody adds without finding this file.
  getCurrentPageFilter: $state => filter => {
    return $state.currentPage[filter] ?? 0;
  },
  getCurrentPage: $state => {
    return $state.currentPage;
  },
};

export const actions = {
  setCurrentPage({ commit }, { filter, page }) {
    commit(types.default.SET_CURRENT_PAGE, { filter, page });
  },
  setEndReached({ commit }, { filter }) {
    commit(types.default.SET_CONVERSATION_END_REACHED, { filter });
  },
  reset({ commit }) {
    commit(types.default.CLEAR_CONVERSATION_PAGE);
  },
};

export const mutations = {
  [types.default.SET_CURRENT_PAGE]: ($state, { filter, page }) => {
    $state.currentPage = {
      ...$state.currentPage,
      [filter]: page,
    };
  },
  [types.default.SET_CONVERSATION_END_REACHED]: ($state, { filter }) => {
    // Todos holds both dropdown states: once it is exhausted, so are they.
    if (filter === 'all') {
      $state.hasEndReached = {
        ...$state.hasEndReached,
        unanswered: true,
        answered: true,
      };
    }
    $state.hasEndReached = {
      ...$state.hasEndReached,
      [filter]: true,
    };
  },
  [types.default.CLEAR_CONVERSATION_PAGE]: $state => {
    $state.currentPage = {
      all: 0,
      unanswered: 0,
      answered: 0,
      groups: 0,
      appliedFilters: 0,
    };

    $state.hasEndReached = {
      all: false,
      unanswered: false,
      answered: false,
      groups: false,
      appliedFilters: false,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
