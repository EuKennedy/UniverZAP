// Shared catalog used by both the panel (checklist) and the tour (driver.js
// step config). Keep the keys and the readiness `flag` mapping in sync with
// the OnboardingStateController on the backend.

export const ONBOARDING_TOUR_EVENTS = Object.freeze({
  START: 'onboarding-tour:start',
  EXIT: 'onboarding-tour:exit',
  STEP_CHANGED: 'onboarding-tour:step-changed',
  COMPLETED: 'onboarding-tour:completed',
});

// Each panel step maps a readiness flag to a deep-link inside the dashboard.
// Routes returned from `route(accountId)` are passed to vue-router via
// `router.push(path)`.
export const buildStepCatalog = ({ t, flags }) => [
  {
    key: 'inbox',
    icon: 'i-lucide-message-circle',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.CTA'),
    done: flags.has_inbox,
    route: accountId => `/app/accounts/${accountId}/settings/inboxes/new`,
  },
  {
    key: 'team_members',
    icon: 'i-lucide-user-plus',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.CTA'),
    done: flags.has_team_members,
    route: accountId => `/app/accounts/${accountId}/agents/new`,
  },
  {
    key: 'team_group',
    icon: 'i-lucide-users',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.CTA'),
    done: flags.has_team_group,
    route: accountId => `/app/accounts/${accountId}/settings/teams/new`,
  },
  {
    key: 'assistant',
    icon: 'i-lucide-sparkles',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.CTA'),
    done: flags.has_assistant,
    route: accountId => `/app/accounts/${accountId}/athenas/wizard`,
  },
  {
    key: 'first_reply',
    icon: 'i-lucide-send',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.CTA'),
    done: flags.has_first_reply,
    route: accountId => `/app/accounts/${accountId}/dashboard`,
  },
];

// Driver.js tour: anchored to stable data attributes on the dashboard chrome.
// Each step exposes `dataOnboarding` so we can add `data-onboarding="..."`
// to the target element (sidebar nav buttons, primary CTAs). The tour
// engine queries `[data-onboarding="<key>"]` at runtime.
export const buildTourSteps = ({ t }) => [
  {
    key: 'welcome',
    fullscreen: true,
    title: t('ONBOARDING_TOUR.TOUR.WELCOME_TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.WELCOME_BODY'),
    primaryLabel: t('ONBOARDING_TOUR.TOUR.WELCOME_CTA'),
    secondaryLabel: t('ONBOARDING_TOUR.TOUR.WELCOME_SKIP'),
  },
  {
    key: 'sidebar-conversations',
    dataOnboarding: 'sidebar-conversations',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.DESCRIPTION'),
    side: 'right',
    align: 'start',
  },
  {
    key: 'add-inbox',
    dataOnboarding: 'add-inbox',
    requireFlag: 'has_inbox',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => `/app/accounts/${accountId}/settings/inboxes/new`,
  },
  {
    key: 'agents-nav',
    dataOnboarding: 'agents-nav',
    requireFlag: 'has_team_members',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => `/app/accounts/${accountId}/settings/agents/new`,
  },
  {
    key: 'teams-nav',
    dataOnboarding: 'teams-nav',
    requireFlag: 'has_team_group',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => `/app/accounts/${accountId}/settings/teams/new`,
  },
  {
    key: 'athenas-nav',
    dataOnboarding: 'athenas-nav',
    requireFlag: 'has_assistant',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => `/app/accounts/${accountId}/athenas`,
  },
  {
    key: 'finish',
    fullscreen: true,
    title: t('ONBOARDING_TOUR.TOUR.FINISH_TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.FINISH_BODY'),
    primaryLabel: t('ONBOARDING_TOUR.TOUR.FINISH_CTA'),
    confetti: true,
  },
];
