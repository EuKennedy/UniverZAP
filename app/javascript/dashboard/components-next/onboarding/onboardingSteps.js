// Shared catalog used by both the panel (checklist) and the tour (driver.js
// step config). Keep the keys and the readiness `flag` mapping in sync with
// the OnboardingStateController on the backend. Routes are returned as
// vue-router `{ name, params }` location descriptors so we never have to
// hardcode dashboard URLs in two places.

export const ONBOARDING_TOUR_EVENTS = Object.freeze({
  START: 'onboarding-tour:start',
  EXIT: 'onboarding-tour:exit',
  STEP_CHANGED: 'onboarding-tour:step-changed',
  COMPLETED: 'onboarding-tour:completed',
});

export const buildStepCatalog = ({ t, flags }) => [
  {
    key: 'inbox',
    icon: 'i-lucide-message-circle',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.CTA'),
    done: flags.has_inbox,
    route: accountId => ({
      name: 'settings_inbox_new',
      params: { accountId },
    }),
  },
  {
    key: 'team_members',
    icon: 'i-lucide-user-plus',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.CTA'),
    done: flags.has_team_members,
    route: accountId => ({ name: 'agent_list', params: { accountId } }),
  },
  {
    key: 'team_group',
    icon: 'i-lucide-users',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.CTA'),
    done: flags.has_team_group,
    route: accountId => ({
      name: 'settings_teams_new',
      params: { accountId },
    }),
  },
  {
    key: 'assistant',
    icon: 'i-lucide-sparkles',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.CTA'),
    done: flags.has_assistant,
    route: accountId => ({
      name: 'athenas_assistant_wizard',
      params: { accountId },
    }),
  },
  {
    key: 'first_reply',
    icon: 'i-lucide-send',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.TITLE'),
    description: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.DESCRIPTION'),
    cta: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.CTA'),
    done: flags.has_first_reply,
    route: accountId => ({ name: 'home', params: { accountId } }),
  },
];

// Driver.js tour: anchored to stable data attributes on the dashboard chrome.
// `dataOnboarding` matches the value passed to `data-onboarding="..."` on the
// target element. `navigateTo` is a vue-router location descriptor (same
// shape as the panel routes) so the tour pre-navigates when a step lives on
// a different page.
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
    navigateTo: accountId => ({
      name: 'settings_inbox_list',
      params: { accountId },
    }),
  },
  {
    key: 'agents-nav',
    dataOnboarding: 'agents-nav',
    requireFlag: 'has_team_members',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => ({ name: 'agent_list', params: { accountId } }),
  },
  {
    key: 'teams-nav',
    dataOnboarding: 'teams-nav',
    requireFlag: 'has_team_group',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => ({
      name: 'settings_teams_list',
      params: { accountId },
    }),
  },
  {
    key: 'athenas-nav',
    dataOnboarding: 'athenas-nav',
    requireFlag: 'has_assistant',
    title: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.DESCRIPTION'),
    side: 'right',
    align: 'start',
    navigateTo: accountId => ({
      name: 'athenas_assistants_index',
      params: { accountId },
    }),
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
