// Shared catalog used by both the panel (checklist) and the tour
// (custom Spotlight component). Keep the keys and the readiness `flag`
// mapping in sync with `OnboardingStateController` on the backend.
// Routes are returned as vue-router `{ name, params }` location
// descriptors so we never have to hardcode dashboard URLs twice.

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

// Guided spotlight tour. Each step anchors to a stable `data-onboarding`
// attribute on the dashboard chrome. Knobs:
//
// - `chapter`     storytelling label shown as the eyebrow above the title
//                 ("Chapter 2 · Inbox setup"). Groups the journey into
//                 ClickUp-style acts so the user senses progress.
// - `clickToAdvance` opts the step into auto-advance when the user actually
//                 clicks the highlighted target.
// - `navigateTo`  pre-navigates when a step lives on a different page.
// - `voice`       optional override for the SpeechSynthesis narrator (off
//                 by default; falls back to `body` if missing).
// - `selectors`   fallback CSS selectors if the `data-onboarding` attribute
//                 is absent (theme overrides, A/B test variants, etc.).
export const buildTourSteps = ({ t }) => [
  {
    key: 'welcome',
    fullscreen: true,
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.WELCOME'),
    title: t('ONBOARDING_TOUR.TOUR.WELCOME_TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.WELCOME_BODY'),
    primaryLabel: t('ONBOARDING_TOUR.TOUR.WELCOME_CTA'),
    secondaryLabel: t('ONBOARDING_TOUR.TOUR.WELCOME_SKIP'),
  },
  {
    key: 'sidebar-conversations',
    dataOnboarding: 'sidebar-conversations',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.INBOX'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.FIRST_REPLY.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
  },
  {
    key: 'add-inbox',
    dataOnboarding: 'add-inbox',
    requireFlag: 'has_inbox',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.INBOX'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.INBOX.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'settings_inbox_list',
      params: { accountId },
    }),
  },
  {
    key: 'agents-nav',
    dataOnboarding: 'agents-nav',
    requireFlag: 'has_team_members',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.TEAM'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
    navigateTo: accountId => ({ name: 'agent_list', params: { accountId } }),
  },
  {
    key: 'teams-nav',
    dataOnboarding: 'teams-nav',
    requireFlag: 'has_team_group',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.TEAM'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_GROUP.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'settings_teams_list',
      params: { accountId },
    }),
  },
  {
    key: 'athenas-nav',
    dataOnboarding: 'athenas-nav',
    requireFlag: 'has_assistant',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.AI'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'athenas_assistants_index',
      params: { accountId },
    }),
  },
  {
    key: 'kanban-nav',
    dataOnboarding: 'kanban-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.PIPELINE'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.KANBAN.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.KANBAN.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'kanban_overview',
      params: { accountId },
    }),
  },
  {
    key: 'contacts-nav',
    dataOnboarding: 'contacts-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.CONTACTS'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.CONTACTS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.CONTACTS.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'contacts_dashboard_index',
      params: { accountId },
    }),
  },
  {
    key: 'reports-nav',
    dataOnboarding: 'reports-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.REPORTS'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.REPORTS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.REPORTS.DESCRIPTION'),
    side: 'right',
    align: 'start',
    clickToAdvance: true,
  },
  {
    key: 'finish',
    fullscreen: true,
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.FINISH'),
    title: t('ONBOARDING_TOUR.TOUR.FINISH_TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.FINISH_BODY'),
    primaryLabel: t('ONBOARDING_TOUR.TOUR.FINISH_CTA'),
    confetti: true,
  },
];
