import { computed, ref } from 'vue';
import AthenasCreditsAPI from 'dashboard/api/athenasCredits';
import { emitter } from 'shared/helpers/mitt';

// Module-level singleton so the meter chip, banner and modal all read the
// same reactive state. The backend already aggregates everything we need
// (balance + threshold + recent ledger + catalogue) in one payload, so
// we only fetch once per refresh cycle and let the listeners derive
// formatting from `summary`.

const TOP_UP_EVENT = 'athenas-credits:open-top-up';
const REFRESH_EVENT = 'athenas-credits:refresh';
const FIVE_MIN_MS = 5 * 60 * 1000;

const summary = ref(null);
const packages = ref([]);
const pricing = ref(null);
const recentEntries = ref([]);
const isLoading = ref(false);
const isLoaded = ref(false);
const lastError = ref(null);
let lastFetchedAt = 0;

async function refresh({ force = false } = {}) {
  if (isLoading.value) return;
  const fresh = Date.now() - lastFetchedAt < FIVE_MIN_MS;
  if (!force && isLoaded.value && fresh) return;

  isLoading.value = true;
  lastError.value = null;
  try {
    const { data } = await AthenasCreditsAPI.get();
    summary.value = data;
    packages.value = data.packages || [];
    pricing.value = data.pricing || null;
    recentEntries.value = data.recent_entries || [];
    isLoaded.value = true;
    lastFetchedAt = Date.now();
  } catch (error) {
    lastError.value = error;
  } finally {
    isLoading.value = false;
  }
}

const openTopUpModal = (reason = 'manual') => {
  emitter.emit(TOP_UP_EVENT, { reason });
};

export function useAthenasCredits() {
  const balanceCents = computed(() => summary.value?.balance_cents_brl ?? 0);
  const balanceBrl = computed(() => (balanceCents.value / 100).toFixed(2));
  const lifetimeGrantedCents = computed(
    () => summary.value?.lifetime_granted_cents_brl ?? 0
  );
  const burnRatePerDay = computed(
    () => summary.value?.burn_rate_cents_per_day ?? 0
  );
  const daysRemaining = computed(
    () => summary.value?.estimated_days_remaining ?? null
  );

  // Status comes from the backend so the UI never disagrees with the
  // gate. Mirror the four states explicitly so consumers can switch on
  // them without re-deriving thresholds.
  const status = computed(() => summary.value?.threshold_status || 'ok');
  const isOk = computed(() => status.value === 'ok');
  const isWarn80 = computed(() => status.value === 'warn_80');
  const isWarn95 = computed(() => status.value === 'warn_95');
  const isExhausted = computed(() => status.value === 'exhausted');
  const showBanner = computed(
    () => isWarn80.value || isWarn95.value || isExhausted.value
  );

  const percentRemaining = computed(() => {
    const denom = lifetimeGrantedCents.value || 1;
    return Math.max(
      0,
      Math.min(100, Math.round((balanceCents.value / denom) * 100))
    );
  });

  return {
    summary,
    packages,
    pricing,
    recentEntries,
    balanceCents,
    balanceBrl,
    burnRatePerDay,
    daysRemaining,
    status,
    isOk,
    isWarn80,
    isWarn95,
    isExhausted,
    showBanner,
    percentRemaining,
    isLoading,
    isLoaded,
    lastError,
    refresh,
    openTopUpModal,
    TOP_UP_EVENT,
    REFRESH_EVENT,
  };
}
