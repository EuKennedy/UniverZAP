import { mount, flushPromises } from '@vue/test-utils';
import AthenasBelezakiConnect from '../AthenasBelezakiConnect.vue';

const belezakiConnection = vi.fn();
const connectBelezaki = vi.fn();
const disconnectBelezaki = vi.fn();
const alerts = vi.fn();

vi.mock('dashboard/api/athenas', () => ({
  default: {
    belezakiConnection: (...args) => belezakiConnection(...args),
    connectBelezaki: (...args) => connectBelezaki(...args),
    disconnectBelezaki: (...args) => disconnectBelezaki(...args),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alerts(...args),
}));

// The key IS the assertion here: every message this card shows is a different
// person's job to fix, so a test that matched rendered prose would pass while
// the operator read the wrong instruction.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Icon: true,
};

const mountCard = (props = {}) =>
  mount(AthenasBelezakiConnect, {
    props: { assistantId: 1, ...props },
    global: { stubs },
  });

describe('AthenasBelezakiConnect.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    belezakiConnection.mockResolvedValue({ data: { connection: null } });
  });

  it('names the salon it is connected to', async () => {
    belezakiConnection.mockResolvedValue({
      data: { connection: { status: 'active', salon_name: 'Studio Bella' } },
    });

    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('Studio Bella');
    expect(wrapper.text()).toContain('ATHENAS.EDIT.BELEZAKI.DISCONNECT');
  });

  it('offers to connect when no salon is bound', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('ATHENAS.EDIT.BELEZAKI.CONNECT');
  });

  // One agenda per agent: two would put two tools with the same name in one
  // payload. Asked BEFORE the round trip so the operator gets the reason and
  // the way out in the same click.
  it('explains instead of calling the API when Google holds the agenda', async () => {
    const wrapper = mountCard({ googleConnected: true });
    await flushPromises();

    await wrapper.find('button').trigger('click');

    expect(connectBelezaki).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('ATHENAS.EDIT.BELEZAKI.ONLY_ONE');
  });

  it('asks the parent to release the Google agenda', async () => {
    const wrapper = mountCard({ googleConnected: true });
    await flushPromises();
    await wrapper.find('button').trigger('click');

    const release = wrapper
      .findAll('button')
      .find(b => b.text() === 'ATHENAS.EDIT.BELEZAKI.DISCONNECT_GOOGLE');
    await release.trigger('click');

    expect(wrapper.emitted('disconnectGoogle')).toHaveLength(1);
  });

  it('connects and reports the new state upward', async () => {
    connectBelezaki.mockResolvedValue({
      data: { connection: { status: 'active', salon_name: 'Bella' } },
    });

    const wrapper = mountCard();
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Bella');
    expect(wrapper.emitted('connected').at(-1)).toEqual([true]);
  });

  // "Not linked" is the operator's onboarding and "not configured" is ours. The
  // card has to say which, or they wait on the wrong person.
  it('shows the reason the salon refused', async () => {
    connectBelezaki.mockRejectedValue({
      response: { data: { error: 'not_linked' } },
    });

    const wrapper = mountCard();
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(alerts).toHaveBeenCalledWith(
      'ATHENAS.EDIT.BELEZAKI.ERRORS.NOT_LINKED'
    );
  });

  // Otherwise the card reads "connected" while the agent has quietly lost the
  // ability to book, and the first to notice is a customer.
  it('says the binding was dropped when the salon refused it', async () => {
    belezakiConnection.mockResolvedValue({
      data: {
        connection: { status: 'revoked', last_error: 'salão sumiu' },
      },
    });

    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('ATHENAS.EDIT.BELEZAKI.DROPPED');
  });

  it('flags a still-bound agenda that failed on the last attempt', async () => {
    belezakiConnection.mockResolvedValue({
      data: {
        connection: {
          status: 'active',
          salon_name: 'Bella',
          last_error: 'chave inválida',
        },
      },
    });

    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.text()).toContain('ATHENAS.EDIT.BELEZAKI.LAST_FAILURE');
  });
});
