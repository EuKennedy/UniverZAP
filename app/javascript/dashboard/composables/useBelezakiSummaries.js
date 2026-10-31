import { ref, watch } from 'vue';
import BelezakiAPI from 'dashboard/api/integrations/belezaki';

// Same size the server accepts in one request.
const BATCH_SIZE = 5;

// Fills in the salon's data for the contacts on screen, one small batch at a
// time and only while `enabled` is on. Changing page abandons the batches left.
export function useBelezakiSummaries(contactIds, enabled) {
  const summaries = ref({});
  let currentRun = 0;

  const isMissing = id =>
    !summaries.value[id] || summaries.value[id].status === 'unavailable';

  const load = async () => {
    currentRun += 1;
    const run = currentRun;
    if (!enabled.value) return;

    const missing = contactIds.value.filter(isMissing);
    for (let start = 0; start < missing.length; start += BATCH_SIZE) {
      const batch = missing.slice(start, start + BATCH_SIZE);
      try {
        // eslint-disable-next-line no-await-in-loop
        const { data } = await BelezakiAPI.getCustomers(batch);
        summaries.value = { ...summaries.value, ...data.customers };
      } catch {
        const failed = batch.map(id => [id, { status: 'unavailable' }]);
        summaries.value = {
          ...summaries.value,
          ...Object.fromEntries(failed),
        };
        return;
      }
      if (run !== currentRun) return;
    }
  };

  watch([contactIds, enabled], load, { immediate: true });

  return { summaries };
}
