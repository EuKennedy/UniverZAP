// Shared catalog used by:
//   - the panel checklist (`buildStepCatalog`)
//   - the main guided spotlight tour (`buildTourSteps`)
//   - the contextual orchestrator that fires mini-tours on first-visit of
//     critical routes (`buildContextualTours`).
//
// Keep the keys and the readiness `flag` mapping in sync with
// `OnboardingStateController` on the backend. Routes are returned as
// vue-router `{ name, params }` location descriptors so we never have to
// hardcode dashboard URLs twice.

export const ONBOARDING_TOUR_EVENTS = Object.freeze({
  START: 'onboarding-tour:start',
  START_CONTEXTUAL: 'onboarding-tour:start-contextual',
  EXIT: 'onboarding-tour:exit',
  STEP_CHANGED: 'onboarding-tour:step-changed',
  COMPLETED: 'onboarding-tour:completed',
  CONTEXTUAL_COMPLETED: 'onboarding-tour:contextual-completed',
});

// Tour identifiers for the catalogue of contextual mini-tours we persist in
// `Account#custom_attributes.onboarding_completed_tours`. Strings are
// stable because the backend doesn't know about them — once a key ships
// you can't rename it without a migration script.
export const CONTEXTUAL_TOUR_KEYS = Object.freeze({
  MAIN: 'main',
  CONVERSATION_VIEW: 'conversation_view',
  ATHENAS_HUB: 'athenas_hub',
  ATHENAS_ASSISTANT: 'athenas_assistant',
  KANBAN_BOARD: 'kanban_board',
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

// Guided main tour. Each step anchors to a stable `data-onboarding`
// attribute on the dashboard chrome. Knobs:
//
// - `chapter`     storytelling label shown as the eyebrow above the title
//                 ("Chapter 02 · Inbox setup"). Groups the journey into
//                 ClickUp-style acts so the user senses progress.
// - `clickToAdvance` opts the step into auto-advance when the user actually
//                 clicks the highlighted target.
// - `navigateTo`  pre-navigates when a step lives on a different page.
// - `requireFlag` skips the step entirely if the readiness flag is already
//                 satisfied — never make the user re-do a finished task.
// - `selectors`   fallback CSS selectors if the `data-onboarding` attribute
//                 is absent (theme overrides, A/B test variants, etc.).
// - `side`        preferred popover side (right|left|top|bottom). Spotlight
//                 will auto-flip if it would overflow the viewport.
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
    title: t('ONBOARDING_TOUR.TOUR.STEPS.SIDEBAR_CONVERSATIONS.TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.STEPS.SIDEBAR_CONVERSATIONS.BODY'),
    side: 'right',
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
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'settings_inbox_list',
      params: { accountId },
    }),
  },
  {
    key: 'athenas-nav',
    dataOnboarding: 'athenas-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.AI'),
    title: t('ONBOARDING_TOUR.TOUR.STEPS.ATHENAS_NAV.TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.STEPS.ATHENAS_NAV.BODY'),
    side: 'right',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'athenas_assistants_index',
      params: { accountId },
    }),
  },
  {
    key: 'athenas-billing',
    dataOnboarding: 'athenas-billing-panel',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.AI'),
    title: t('ONBOARDING_TOUR.TOUR.STEPS.ATHENAS_BILLING.TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.STEPS.ATHENAS_BILLING.BODY'),
    side: 'bottom',
  },
  {
    key: 'athenas-assistant',
    dataOnboarding: 'athenas-new-assistant',
    requireFlag: 'has_assistant',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.AI'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.ASSISTANT.DESCRIPTION'),
    side: 'left',
    clickToAdvance: true,
  },
  {
    key: 'sidebar-kanban',
    dataOnboarding: 'kanban-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.PIPELINE'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.KANBAN.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.KANBAN.DESCRIPTION'),
    side: 'right',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'kanban_overview',
      params: { accountId },
    }),
  },
  {
    key: 'kanban-funnel-selector',
    dataOnboarding: 'kanban-group-by',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.PIPELINE'),
    title: t('ONBOARDING_TOUR.TOUR.STEPS.KANBAN_FUNNEL.TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.STEPS.KANBAN_FUNNEL.BODY'),
    side: 'bottom',
  },
  {
    key: 'kanban-add-task',
    dataOnboarding: 'kanban-add-task',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.PIPELINE'),
    title: t('ONBOARDING_TOUR.TOUR.STEPS.KANBAN_ADD.TITLE'),
    body: t('ONBOARDING_TOUR.TOUR.STEPS.KANBAN_ADD.BODY'),
    side: 'bottom',
  },
  {
    key: 'sidebar-contacts',
    dataOnboarding: 'contacts-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.CONTACTS'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.CONTACTS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.CONTACTS.DESCRIPTION'),
    side: 'right',
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'contacts_dashboard_index',
      params: { accountId },
    }),
  },
  {
    key: 'sidebar-reports',
    dataOnboarding: 'reports-nav',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.REPORTS'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.REPORTS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.REPORTS.DESCRIPTION'),
    side: 'right',
    clickToAdvance: true,
  },
  {
    key: 'agents-nav',
    dataOnboarding: 'agents-nav',
    requireFlag: 'has_team_members',
    chapter: t('ONBOARDING_TOUR.TOUR.CHAPTER.TEAM'),
    title: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.TITLE'),
    body: t('ONBOARDING_TOUR.PANEL.STEPS.TEAM_MEMBERS.DESCRIPTION'),
    side: 'right',
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
    clickToAdvance: true,
    navigateTo: accountId => ({
      name: 'settings_teams_list',
      params: { accountId },
    }),
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

// Contextual mini-tours. The orchestrator fires the first matching entry
// when the user lands on a route they haven't seen before. Routes use
// startsWith matching against `route.name` so `athenas_assistant_edit` and
// `athenas_assistant_wizard` can share a tour without listing every variant.
//
// Anatomy of a contextual tour:
//   key         — stable identifier persisted in custom_attributes
//   matches     — array of route.name prefixes that trigger the tour
//   steps       — same shape as the main tour entries (spotlight or
//                 fullscreen). Mini-tours are usually 2-4 steps.
export const buildContextualTours = ({ t }) => [
  {
    key: CONTEXTUAL_TOUR_KEYS.CONVERSATION_VIEW,
    matches: ['inbox_conversation', 'conversation_through_inbox'],
    steps: [
      {
        key: 'conv-athenas-balance',
        dataOnboarding: 'conv-athenas-balance',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.CHAPTER'),
        title: t(
          'ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.ATHENAS_BALANCE.TITLE'
        ),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.ATHENAS_BALANCE.BODY'),
        side: 'bottom',
      },
      {
        key: 'conv-resolve',
        dataOnboarding: 'conv-resolve-action',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.RESOLVE.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.RESOLVE.BODY'),
        side: 'bottom',
      },
      {
        key: 'conv-move-kanban',
        dataOnboarding: 'conv-move-kanban',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.MOVE_KANBAN.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.MOVE_KANBAN.BODY'),
        side: 'bottom',
      },
      {
        key: 'conv-autopilot',
        dataOnboarding: 'conv-autopilot',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.AUTOPILOT.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.CONVERSATION.AUTOPILOT.BODY'),
        side: 'bottom',
      },
    ],
  },
  {
    key: CONTEXTUAL_TOUR_KEYS.ATHENAS_HUB,
    matches: ['athenas_assistants_index'],
    steps: [
      {
        key: 'athenas-hub-billing',
        dataOnboarding: 'athenas-billing-panel',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_HUB.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_HUB.BILLING.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_HUB.BILLING.BODY'),
        side: 'bottom',
      },
      {
        key: 'athenas-hub-new',
        dataOnboarding: 'athenas-new-assistant',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_HUB.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_HUB.NEW_ASSISTANT.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_HUB.NEW_ASSISTANT.BODY'),
        side: 'left',
      },
    ],
  },
  {
    key: CONTEXTUAL_TOUR_KEYS.ATHENAS_ASSISTANT,
    matches: ['athenas_assistant_edit', 'athenas_assistant_wizard'],
    steps: [
      {
        key: 'asst-name',
        dataOnboarding: 'asst-name',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.NAME.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.NAME.BODY'),
        side: 'bottom',
      },
      {
        key: 'asst-prompt',
        dataOnboarding: 'asst-prompt',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.PROMPT.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.PROMPT.BODY'),
        side: 'right',
      },
      {
        key: 'asst-rag',
        dataOnboarding: 'asst-rag',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.RAG.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.ATHENAS_ASSISTANT.RAG.BODY'),
        side: 'right',
      },
    ],
  },
  {
    key: CONTEXTUAL_TOUR_KEYS.KANBAN_BOARD,
    matches: ['kanban_board', 'kanban_overview'],
    steps: [
      {
        key: 'kanban-funnel',
        dataOnboarding: 'kanban-group-by',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.KANBAN.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.KANBAN.FUNNEL.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.KANBAN.FUNNEL.BODY'),
        side: 'bottom',
      },
      {
        key: 'kanban-add',
        dataOnboarding: 'kanban-add-task',
        chapter: t('ONBOARDING_TOUR.CONTEXTUAL.KANBAN.CHAPTER'),
        title: t('ONBOARDING_TOUR.CONTEXTUAL.KANBAN.ADD.TITLE'),
        body: t('ONBOARDING_TOUR.CONTEXTUAL.KANBAN.ADD.BODY'),
        side: 'bottom',
      },
    ],
  },
];

// Resolve a contextual tour for the current route. Returns the first
// matching tour entry, or null when there's no orchestrated mini-tour for
// this view. `routeName` is the literal vue-router route.name.
export const findContextualTourForRoute = ({ tours, routeName }) => {
  if (!routeName) return null;
  return (
    tours.find(tour =>
      tour.matches?.some(prefix => routeName.startsWith(prefix))
    ) || null
  );
};
