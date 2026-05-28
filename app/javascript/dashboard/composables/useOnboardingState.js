import { computed, ref } from 'vue';
import OnboardingStateAPI from 'dashboard/api/onboardingState';
import { useAccount } from 'dashboard/composables/useAccount';

// Module-level singleton so every consumer sees the same reactive state.
// The launcher, panel, tour and contextual orchestrator all read these
// values; persistence helpers route everything through the singleton
// resource `/onboarding_state` (PATCH) so a backend recompute of
// `completed`/`regressed_steps` happens on every write.
const flags = ref({
  has_inbox: false,
  has_team_members: false,
  has_team_group: false,
  has_assistant: false,
  has_first_reply: false,
});
// Mirror of the backend `completed` flag — it uses a lenient rule (inbox
// present) so accounts that already look configured don't get haunted by
// the launcher.
const completedFromApi = ref(false);
// Backend-computed list of readiness flags that were green at the moment
// the user finished the main tour but have since flipped back to false.
// Drives the "Finish what you undid" launcher state without us needing to
// re-derive the diff client-side.
const regressedStepsFromApi = ref([]);
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
    const {
      custom_attributes: attrs,
      completed,
      regressed_steps: regressed,
      ...readiness
    } = data;
    flags.value = readiness;
    completedFromApi.value = Boolean(completed);
    regressedStepsFromApi.value = Array.isArray(regressed) ? regressed : [];
    customAttrs.value = attrs || {};
    isLoaded.value = true;
    lastFetchedAt = Date.now();
  } catch (error) {
    lastError.value = error;
  } finally {
    isLoading.value = false;
  }
}

// Persist the onboarding `custom_attributes` patch via the dedicated
// `PATCH /onboarding_state` endpoint. Returns the fresh state so we keep
// `regressed_steps` and the cached snapshot in lockstep.
async function persistPatch(patch) {
  const next = { ...customAttrs.value, ...patch };
  customAttrs.value = next;
  try {
    const { data } = await OnboardingStateAPI.patch(patch);
    const {
      custom_attributes: attrs,
      completed,
      regressed_steps: regressed,
      ...readiness
    } = data;
    flags.value = readiness;
    completedFromApi.value = Boolean(completed);
    regressedStepsFromApi.value = Array.isArray(regressed) ? regressed : [];
    customAttrs.value = attrs || {};
    lastFetchedAt = Date.now();
  } catch (error) {
    lastError.value = error;
  }
}

export function useOnboardingState() {
  // `useAccount` still exposes a fallback `updateAccount` mutator we keep
  // around for legacy panels that haven't migrated to the singleton patch
  // path. Anything onboarding-shaped should go through `persistPatch`.
  useAccount();

  const score = computed(() => {
    const total = Object.keys(flags.value).length;
    const done = Object.values(flags.value).filter(Boolean).length;
    return {
      done,
      total,
      percent: total ? Math.round((done / total) * 100) : 0,
    };
  });

  // `isComplete` follows the backend signal — once the tenant has the
  // essentials (inbox present) we consider onboarding done and the FAB
  // hides. The panel's progress bar still walks all 5 so the user can
  // finish what they want.
  const isComplete = computed(() => completedFromApi.value);
  const isFullyComplete = computed(
    () => score.value.done === score.value.total
  );
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

  // Catalogue of contextual mini-tours the user has finished. Stored as a
  // string[] of tour keys so adding new mini-tours never needs a migration.
  const completedTours = computed(() =>
    Array.isArray(customAttrs.value.onboarding_completed_tours)
      ? customAttrs.value.onboarding_completed_tours
      : []
  );
  const hasSeenContextualTour = key => completedTours.value.includes(key);

  // Server-computed list of readiness flags that flipped red after the
  // user finished the main tour. The launcher uses this to re-engage with
  // targeted copy instead of restarting the whole journey.
  const regressedSteps = computed(() => regressedStepsFromApi.value);

  const markTourCompleted = async () => {
    // Snapshot the readiness flags at completion time so the backend can
    // detect regressions later (anything green now that turns red counts).
    const snapshot = { ...flags.value };
    await persistPatch({
      onboarding_tour_completed_at: new Date().toISOString(),
      onboarding_explicit_dismiss: false,
      onboarding_readiness_snapshot: snapshot,
    });
  };

  const markContextualTourCompleted = async key => {
    if (!key) return;
    const next = Array.from(new Set([...completedTours.value, key]));
    await persistPatch({ onboarding_completed_tours: next });
  };

  const resetContextualTour = async key => {
    if (!key) return;
    const next = completedTours.value.filter(k => k !== key);
    await persistPatch({ onboarding_completed_tours: next });
  };

  const dismissExplicit = () =>
    persistPatch({ onboarding_explicit_dismiss: true });
  const resetDismiss = () =>
    persistPatch({ onboarding_explicit_dismiss: false });

  const setLastStepIndex = index =>
    persistPatch({ onboarding_last_step_index: index });

  return {
    flags,
    score,
    isComplete,
    isFullyComplete,
    isFresh,
    isLoaded,
    isLoading,
    lastError,
    tourCompletedAt,
    explicitDismiss,
    lastStepIndex,
    completedTours,
    regressedSteps,
    hasSeenContextualTour,
    refresh,
    markTourCompleted,
    markContextualTourCompleted,
    resetContextualTour,
    dismissExplicit,
    resetDismiss,
    setLastStepIndex,
  };
}
