import { computed } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import AccountSettings from '../Index.vue';
import AccountId from '../components/AccountId.vue';

const store = createStore({
  state: { records: [] },
  getters: {
    'accounts/getAccount': state => id =>
      state.records.find(record => record.id === id) || {},
    'accounts/getUIFlags': () => ({ isFetchingItem: false }),
    'accounts/isFeatureEnabledonAccount': () => () => false,
    'globalConfig/isOnChatwootCloud': () => false,
  },
  mutations: {
    setAccounts(state, records) {
      state.records = records;
    },
  },
});

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: computed(() => 5),
    currentAccount: computed(
      () => store.getters['accounts/getAccount'](5) || {}
    ),
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: {}, updateUISettings: vi.fn() }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ enabledLanguages: [] }),
}));

const account = {
  id: 5,
  name: 'BEAUTY CENTER BH LOURDES',
  locale: 'pt_BR',
  domain: '',
  support_email: '',
  features: {},
};

// App.vue fetches the account only after the route has rendered, so on a
// page reload this view mounts with an empty accounts store.
describe('Account settings after a page reload', () => {
  beforeEach(() => {
    store.commit('setAccounts', []);
  });

  it('waits for the account before showing its id', async () => {
    const wrapper = shallowMount(AccountSettings, {
      global: { plugins: [store] },
    });
    expect(wrapper.findComponent(AccountId).exists()).toBe(false);

    store.commit('setAccounts', [account]);
    await flushPromises();

    expect(wrapper.findComponent(AccountId).exists()).toBe(true);
  });

  it('fills the form when the account arrives after mounting', async () => {
    const wrapper = shallowMount(AccountSettings, {
      global: { plugins: [store] },
    });
    expect(wrapper.vm.name).toBeFalsy();

    store.commit('setAccounts', [account]);
    await flushPromises();

    expect(wrapper.vm.name).toBe('BEAUTY CENTER BH LOURDES');
    expect(wrapper.vm.locale).toBe('pt_BR');
  });
});
