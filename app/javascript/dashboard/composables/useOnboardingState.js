import { computed, ref } from 'vue';
import OnboardingStateAPI from 'dashboard/api/onboardingState';
import { useAccount } from 'dashboard/composables/useAccount';

// Module-level singleton so every consumer sees the same reactive state.
// The launcher, panel, and tour all read these values; persistence helpers
// only touch them through updateAccount + a re-fetch.
const flags = ref({
  has_inbox: false,
  has_team_members: false,
  has_team_group: false,
  has_assistant: false,
  has_first_reply: false,
});
const customAttrs = ref({});
const isLoaded = ref(false);
const isLoading = ref(false);
const lastError = ref(null);

const FIVE_MIN = 5 * 60 * 1000;
let lastFetchedAt = 0;

async function refresh({ force = false } = {}) {
  if (isLoading.value) return;
  const fresh = Date.now() - lastFetchedAt < FIVE_MIN;
  if (!force && isLoaded.value && fresh) return;

  isLoading.value = true;
  lastError.value = null;
  try {
    const { data } = await OnboardingStateAPI.get();
    const { custom_attributes: attrs, ...readiness } = data;
    flags.value = readiness;
    customAttrs.value = attrs || {};
    isLoaded.value = true;
    lastFetchedAt = Date.now();
  } catch (error) {
    lastError.value = error;
  } finally {
    isLoading.value = false;
  }
}

export function useOnboardingState() {
  const { currentAccount, updateAccount } = useAccount();

  const score = computed(() => {
    const total = Object.keys(flags.value).length;
    const done = Object.values(flags.value).filter(Boolean).length;
    return {
      done,
      total,
      percent: total ? Math.round((done / total) * 100) : 0,
    };
  });

  const isComplete = computed(() => score.value.done === score.value.total);
  const isFresh = computed(() => score.value.done === 0);

  const tourCompletedAt = computed(
    () => customAttrs.value.onboarding_tour_completed_at || null
  );
  const explicitDismiss = computed(
    () => customAttrs.value.onboarding_explicit_dismiss === true
  );
  const lastStepIndex = computed(
    () => customAttrs.value.onboarding_last_step_index ?? 0
  );

  // Persist `onboarding_*` keys into Account#custom_attributes (JSONB).
  // Merges with existing custom_attributes to avoid wiping unrelated keys.
  const persist = async patch => {
    const base = currentAccount.value?.custom_attributes || {};
    const next = { ...base, ...customAttrs.value, ...patch };
    customAttrs.value = next;
    try {
      await updateAccount({ custom_attributes: next });
    } catch (error) {
      lastError.value = error;
    }
  };

  const markTourCompleted = () =>
    persist({
      onboarding_tour_completed_at: new Date().toISOString(),
      onboarding_explicit_dismiss: false,
    });

  const dismissExplicit = () => persist({ onboarding_explicit_dismiss: true });
  const resetDismiss = () => persist({ onboarding_explicit_dismiss: false });

  const setLastStepIndex = index =>
    persist({ onboarding_last_step_index: index });

  return {
    flags,
    score,
    isComplete,
    isFresh,
    isLoaded,
    isLoading,
    lastError,
    tourCompletedAt,
    explicitDismiss,
    lastStepIndex,
    refresh,
    markTourCompleted,
    dismissExplicit,
    resetDismiss,
    setLastStepIndex,
  };
}
