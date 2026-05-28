<script setup>
import { computed, onBeforeUnmount, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { emitter } from 'shared/helpers/mitt';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useOnboardingState } from 'dashboard/composables/useOnboardingState';
import {
  ONBOARDING_TOUR_EVENTS,
  buildContextualTours,
  findContextualTourForRoute,
} from './onboardingSteps';

// Headless orchestrator — no template. Watches the route and fires the
// first matching contextual mini-tour the operator hasn't seen yet. This
// is what gives the product a ClickUp/Stripe-grade feel: every important
// view introduces itself the first time you visit it, then quietly stops
// bothering you forever (the completion key is persisted server-side).
//
// Guardrails:
// - Only admins see mini-tours (atendentes get a clean dashboard).
// - We never start a contextual tour while the main tour is still
//   in-flight (avoids stacking spotlights on top of each other).
// - The backend `regressed_steps` signal can deliberately re-open
//   specific mini-tours via `resetContextualTour`, e.g. when a Kanban
//   funnel gets deleted we want the next visit to walk the user through
//   setting one up again.

const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();
const { isLoaded, refresh, hasSeenContextualTour, completedTours } =
  useOnboardingState();

let mainTourActive = false;
let activeContextualKey = null;

const onMainStart = () => {
  mainTourActive = true;
};
const onMainComplete = () => {
  mainTourActive = false;
};
const onMainExit = ({ contextual } = {}) => {
  if (contextual) {
    activeContextualKey = null;
  } else {
    mainTourActive = false;
  }
};
const onContextualComplete = ({ key } = {}) => {
  if (key && key === activeContextualKey) activeContextualKey = null;
};

const tours = computed(() => buildContextualTours({ t }));

const fireForRoute = routeName => {
  if (!routeName) return;
  if (!isAdmin.value) return;
  if (!isLoaded.value) return;
  if (mainTourActive) return;
  if (activeContextualKey) return;

  const tour = findContextualTourForRoute({
    tours: tours.value,
    routeName,
  });
  if (!tour) return;
  if (hasSeenContextualTour(tour.key)) return;

  activeContextualKey = tour.key;
  // Defer a tick so route-level components have a chance to mount and
  // paint their `data-onboarding` anchors before the spotlight tries to
  // resolve them.
  window.setTimeout(() => {
    emitter.emit(ONBOARDING_TOUR_EVENTS.START_CONTEXTUAL, {
      key: tour.key,
      steps: tour.steps,
    });
  }, 600);
};

// Re-evaluate on every route change AND on first load once readiness has
// arrived. The double-fire (watch + onMounted) is cheap because the early
// returns above bail out when the tour was already seen.
watch(
  () => route.name,
  name => fireForRoute(name)
);
watch(isLoaded, ready => {
  if (ready) fireForRoute(route.name);
});
// Also re-check when `completedTours` changes — that's how we hot-react if
// another tab marks a tour completed while we're still on the same route.
watch(completedTours, () => fireForRoute(route.name), { deep: true });

onMounted(() => {
  refresh();
  emitter.on(ONBOARDING_TOUR_EVENTS.START, onMainStart);
  emitter.on(ONBOARDING_TOUR_EVENTS.COMPLETED, onMainComplete);
  emitter.on(ONBOARDING_TOUR_EVENTS.EXIT, onMainExit);
  emitter.on(ONBOARDING_TOUR_EVENTS.CONTEXTUAL_COMPLETED, onContextualComplete);
  fireForRoute(route.name);
});

onBeforeUnmount(() => {
  emitter.off(ONBOARDING_TOUR_EVENTS.START, onMainStart);
  emitter.off(ONBOARDING_TOUR_EVENTS.COMPLETED, onMainComplete);
  emitter.off(ONBOARDING_TOUR_EVENTS.EXIT, onMainExit);
  emitter.off(
    ONBOARDING_TOUR_EVENTS.CONTEXTUAL_COMPLETED,
    onContextualComplete
  );
});
</script>

<template>
  <!-- Headless orchestrator — UI is rendered by `OnboardingTour.vue`.
       Vue still needs a root element so we render an `aria-hidden` span. -->
  <span aria-hidden="true" class="hidden" />
</template>
