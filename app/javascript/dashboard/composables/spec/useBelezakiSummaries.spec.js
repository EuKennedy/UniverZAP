import { nextTick, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import BelezakiAPI from 'dashboard/api/integrations/belezaki';
import { useBelezakiSummaries } from '../useBelezakiSummaries';

vi.mock('dashboard/api/integrations/belezaki', () => ({
  default: { getCustomers: vi.fn() },
}));

const answer = ids => ({
  data: {
    customers: Object.fromEntries(ids.map(id => [id, { status: 'ok' }])),
  },
});

describe('useBelezakiSummaries', () => {
  beforeEach(() => {
    BelezakiAPI.getCustomers.mockReset();
    BelezakiAPI.getCustomers.mockImplementation(async ids => answer(ids));
  });

  it('calls nothing while it is off', async () => {
    useBelezakiSummaries(ref([1, 2, 3]), ref(false));
    await flushPromises();
    expect(BelezakiAPI.getCustomers).not.toHaveBeenCalled();
  });

  it('asks in batches of five, one after the other', async () => {
    const ids = ref(Array.from({ length: 12 }, (_, index) => index + 1));
    const { summaries } = useBelezakiSummaries(ids, ref(true));
    await flushPromises();

    const batches = BelezakiAPI.getCustomers.mock.calls.map(([batch]) => batch);
    expect(batches.map(batch => batch.length)).toEqual([5, 5, 2]);
    expect(Object.keys(summaries.value)).toHaveLength(12);
  });

  it('does not ask again for what it already has', async () => {
    const ids = ref([1, 2]);
    useBelezakiSummaries(ids, ref(true));
    await flushPromises();

    ids.value = [2, 3];
    await flushPromises();

    expect(BelezakiAPI.getCustomers).toHaveBeenLastCalledWith([3]);
  });

  it('starts when turned on', async () => {
    const enabled = ref(false);
    useBelezakiSummaries(ref([1]), enabled);

    enabled.value = true;
    await nextTick();
    await flushPromises();

    expect(BelezakiAPI.getCustomers).toHaveBeenCalledTimes(1);
  });

  it('stops at a failed batch and marks it unavailable', async () => {
    BelezakiAPI.getCustomers.mockRejectedValue(new Error('down'));
    const ids = ref([1, 2, 3, 4, 5, 6]);
    const { summaries } = useBelezakiSummaries(ids, ref(true));
    await flushPromises();

    expect(BelezakiAPI.getCustomers).toHaveBeenCalledTimes(1);
    expect(summaries.value[1].status).toBe('unavailable');
  });
});
