import * as types from '../../../mutation-types';
import { mutations } from '../../conversationPage';

describe('#mutations', () => {
  describe('#SET_CURRENT_PAGE', () => {
    it('set current page correctly', () => {
      const state = { currentPage: { me: 1 } };
      mutations[types.default.SET_CURRENT_PAGE](state, {
        filter: 'me',
        page: 2,
      });
      expect(state.currentPage).toEqual({
        me: 2,
      });
    });
  });

  describe('#CLEAR_CONVERSATION_PAGE', () => {
    it('resets the state to initial state', () => {
      const state = {
        currentPage: { all: 3, unanswered: 2, answered: 1, groups: 1 },
        hasEndReached: { all: true, unanswered: true, groups: true },
      };
      mutations[types.default.CLEAR_CONVERSATION_PAGE](state);
      expect(state).toEqual({
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
          appliedFilters: false,
        },
      });
    });
  });

  describe('#SET_CONVERSATION_END_REACHED', () => {
    it('set conversation end reached correctly', () => {
      const state = {
        hasEndReached: { all: false, unanswered: false, answered: false },
      };
      mutations[types.default.SET_CONVERSATION_END_REACHED](state, {
        filter: 'unanswered',
      });
      expect(state.hasEndReached).toEqual({
        all: false,
        unanswered: true,
        answered: false,
      });
    });

    it('marks both dropdown states as reached once Todos is exhausted', () => {
      const state = {
        hasEndReached: {
          all: false,
          unanswered: false,
          answered: false,
          groups: false,
        },
      };
      mutations[types.default.SET_CONVERSATION_END_REACHED](state, {
        filter: 'all',
      });
      expect(state.hasEndReached).toEqual({
        all: true,
        unanswered: true,
        answered: true,
        groups: false,
      });
    });
  });
});
