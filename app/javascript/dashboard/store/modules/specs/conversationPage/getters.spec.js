import { getters } from '../../conversationPage';

describe('#getters', () => {
  it('getCurrentPage', () => {
    const state = {
      currentPage: {
        me: 1,
        unassigned: 2,
        all: 3,
      },
    };
    expect(getters.getCurrentPage(state)).toHaveProperty('me');
    expect(getters.getCurrentPage(state)).toHaveProperty('unassigned');
    expect(getters.getCurrentPage(state)).toHaveProperty('all');
  });

  it('getCurrentPageFilter', () => {
    const state = {
      currentPage: {
        me: 1,
        unassigned: 2,
        all: 3,
      },
    };
    expect(getters.getCurrentPageFilter(state)('me')).toEqual(1);
    expect(getters.getCurrentPageFilter(state)('unassigned')).toEqual(2);
    expect(getters.getCurrentPageFilter(state)('all')).toEqual(3);
  });

  // The fork's attendance tabs (Aguardando, Em atendimento, Grupos) are not
  // keys of this state. Undefined here became `undefined + 1` = NaN at the call
  // site, every request asked for page NaN, the server answered page 1 for
  // ever, and loadMore never stopped firing.
  it('getCurrentPageFilter starts a tab it never heard of at zero', () => {
    const state = { currentPage: { me: 1 } };

    expect(getters.getCurrentPageFilter(state)('waiting')).toEqual(0);
    expect(getters.getCurrentPageFilter(state)('waiting') + 1).toEqual(1);
  });

  it('getHasEndReached', () => {
    const state = {
      hasEndReached: {
        me: false,
        unassigned: true,
        all: false,
      },
    };
    expect(getters.getHasEndReached(state)('me')).toEqual(false);
    expect(getters.getHasEndReached(state)('unassigned')).toEqual(true);
    expect(getters.getHasEndReached(state)('all')).toEqual(false);
  });
});
