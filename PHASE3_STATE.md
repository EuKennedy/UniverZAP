# Phase 3 — Kanban — Resume State

**Last updated:** 2026-05-14
**Status:** Phase 3.1 shipped (commit pushed, GHA build in progress at pause time).
**Branch:** `univerzap/phase-3-kanban`
**HEAD:** `a04a0a9be7fb417244092fbcb61b10e1524b57a6`

---

## Resume protocol

When user prompts next session, do this first:

1. Read this file.
2. Run `git log --oneline -3 && git status && git branch --show-current` — confirm branch + HEAD match above. If diverged, ask user before continuing.
3. Check GHA: `WebFetch https://github.com/EuKennedy/UniverZAP/actions` — find run for commit `a04a0a9be`. Report status to user.
4. If build green → verify GHCR image `ghcr.io/eukennedy/univerzap:univerzap-phase-3-kanban` published.
5. If build failed → fetch logs, diagnose, fix, push.
6. Ask user: deploy tag strategy (see "Open decisions") AND Phase 3.2 approval.

**Caveman mode** active full. Code/commits normal English.

---

## What shipped in Phase 3.1

**Commit:** `a04a0a9be` — "feat(kanban): introduce funnels, stages and tasks (phase 3.1 schema + API)"
**Diff:** 41 files, +903 lines.

### Migrations
- `db/migrate/20260514180000_create_funnels.rb` — funnels + funnel_inboxes + funnel_agents
- `db/migrate/20260514180100_create_funnel_stages.rb` — stages with status_type enum (active=0, won=1, lost=2), hex color default `#64748B`
- `db/migrate/20260514180200_create_kanban_tasks.rb` — tasks + 4 join tables (assignees/labels/conversations/contacts)

### Models
- `app/models/funnel.rb` — automation_settings allowlist (5 keys), ordered scope, position auto-increment per account
- `app/models/funnel_stage.rb` — hex color regex, status_type enum, ordered by position
- `app/models/kanban_task.rb` — priority enum (none/low/medium/high/urgent), cross-account guards, display_id auto-increment per account
- Join models: `funnel_inbox.rb`, `funnel_agent.rb`, `kanban_task_assignee.rb`, `kanban_task_label.rb`, `kanban_task_conversation.rb`, `kanban_task_contact.rb`
- `app/models/account.rb` — added `has_many :funnels` + `has_many :kanban_tasks` (dependent: destroy_async)

### Policies (Pundit)
- `app/policies/funnel_policy.rb` — index: any account_user; mutations: admin only; scope filters by funnel_agents
- `app/policies/kanban_task_policy.rb` — delegates read/write to FunnelPolicy; destroy admin OR assignee

### Controllers
- `app/controllers/api/v1/accounts/funnels_controller.rb` — REST + apply_associations(inbox_ids, agent_ids)
- `app/controllers/api/v1/accounts/funnel_stages_controller.rb` — REST + `reorder` action (transaction)
- `app/controllers/api/v1/accounts/kanban_tasks_controller.rb` — REST + `move` action + apply_associations(assignee_ids, label_ids, conversation_ids, contact_ids). Path: `/Users/OPERACOES/Downloads/chat-univerzap/univerzap/app/controllers/api/v1/accounts/kanban_tasks_controller.rb`

### Routes (`config/routes.rb`, after `resources :labels` ~line 258)
```ruby
resources :funnels do
  resources :funnel_stages, only: [:index, :show, :create, :update, :destroy] do
    collection do
      post :reorder
    end
  end
  resources :kanban_tasks, only: [:index, :create]
end
resources :kanban_tasks, only: [:show, :update, :destroy] do
  member do
    post :move
  end
end
```

### Jbuilder views
- `app/views/api/v1/accounts/funnels/` — index, show, create, update, _funnel.json.jbuilder
- `app/views/api/v1/accounts/funnel_stages/` — index, show, create, update, _funnel_stage.json.jbuilder
- `app/views/api/v1/accounts/kanban_tasks/` — index, show, create, update, _kanban_task.json.jbuilder

### Factories
- `spec/factories/funnels.rb`
- `spec/factories/funnel_stages.rb`
- `spec/factories/kanban_tasks.rb`

### Specs
- `spec/models/funnel_spec.rb` — associations, validations, position, automation_settings allowlist
- `spec/models/funnel_stage_spec.rb` — color regex, status_type enum
- `spec/models/kanban_task_spec.rb` — associations, display_id increment, cross-funnel/account guards

---

## Data model (from competitor reverse-engineering)

**Source:** Mapped competitor at `https://chat.univerzap.cloud/app/accounts/1/kanban/*` via Claude in Chrome MCP.

### Funnel
- `name` (≤120), `description` (≤2000), `position` (account-scoped), `automation_settings` (jsonb)
- `inboxes` (M:N via funnel_inboxes), `agents` (M:N via funnel_agents)
- Automation keys allowlist:
  - `auto_create_task_for_new_conversation`
  - `auto_assign_task_to_agent`
  - `sync_task_conversation_assignees`
  - `auto_resolve_conversation_on_task_close`
  - `auto_win_task_on_conversation_resolve`

### FunnelStage
- `name` (≤120), `description`, `color` (hex), `position`, `status_type` (active/won/lost)

### KanbanTask
- `title` (≤255), `description` (≤5000), `priority` (none/low/medium/high/urgent), `position`, `start_date`, `due_date`, `display_id` (account-scoped auto-increment)
- `assignees` (M:N users), `task_labels` (M:N labels), `conversations` (M:N), `contacts` (M:N)

### Competitor routes mapped
- `/kanban/overview` — all funnels grid
- `/kanban/:id` — single funnel board
- `/kanban/:id/create` — task create modal
- `/kanban/:id/task/:tid` — task detail modal
- `/kanban/:id/settings` — funnel settings (stages, automations, inboxes, agents)

---

## At-pause state

**GHA build:** Run #12 on `univerzap/phase-3-kanban` — status `in_progress` at pause. Started ~4 min before pause. Previous builds 3:43–22:46.

**Coolify:** Still pointed at staging tag → `univerzap-phase-0-saneamento` image. Phase 3.1 image will publish as `ghcr.io/eukennedy/univerzap:univerzap-phase-3-kanban` once build green.

**Migration:** NOT yet run on staging DB. Coolify Docker entrypoint does NOT run `db:migrate`. Procfile has `release: db:chatwoot_prepare` but unused. Manual step required post-image-publish:
```
docker exec <rails_container> bundle exec rails db:migrate
```

---

## Open decisions for user (ask after resume)

1. **Deploy tag strategy** — two paths:
   - **A:** Merge `univerzap/phase-3-kanban` → `univerzap/phase-0-saneamento` (latter has Coolify `staging` tag pointed at it). PR + merge + auto-deploy.
   - **B:** Temporarily repoint Coolify image tag to `univerzap-phase-3-kanban` for testing, merge later.
   - Recommendation: A if confident in build green. B if want isolated test.

2. **Migration execution** — needs manual run via Coolify terminal after image deploys.

3. **Phase 3.2 approval** — UI work (see next section).

---

## Phase 3.2 — UI (next chunk)

**Scope:** Vue board UI parity with competitor, drag-drop, realtime sync.

### Stack additions
- `vue-draggable-plus` (Sortable.js Vue wrapper) — drag-drop columns + cards
- Pinia stores: `useFunnelStore`, `useKanbanTaskStore`
- ActionCable channel: `FunnelChannel` (per-funnel room, broadcasts on task/stage mutations)

### Routes (Vue Router)
- `/app/accounts/:accountId/kanban/overview` — funnels grid
- `/app/accounts/:accountId/kanban/:funnelId` — board
- `/app/accounts/:accountId/kanban/:funnelId/create` — task create modal
- `/app/accounts/:accountId/kanban/:funnelId/task/:taskId` — task detail modal
- `/app/accounts/:accountId/kanban/:funnelId/settings` — funnel settings

### Components (TBD paths under `app/javascript/dashboard/`)
- `KanbanOverview.vue` — funnels grid with task count + last activity
- `KanbanBoard.vue` — columns + cards, drag-drop wiring
- `KanbanColumn.vue` — stage header (color dot, name, count), sortable list
- `KanbanCard.vue` — title, priority chip, due date, assignees stack, contact badge
- `KanbanTaskModal.vue` — full task editor (title, desc, agentes, etiquetas, conversas, contatos, dates, priority, stage)
- `KanbanFunnelSettings.vue` — name/desc, inboxes multi-select, agents multi-select, stages list (CRUD + reorder), 5 automation toggles
- `KanbanStageEditor.vue` — name, description, color picker, status_type

### Design refs (per global CLAUDE.md)
- Apple / Linear / Stripe — dark-first, editorial typography, motion physics
- Card hover: subtle lift + shadow grow
- Drag ghost: rotated slightly, soft glow
- Empty state: large icon, single-line copy, single CTA
- Mobile: horizontal scroll columns, swipe to switch funnel

### Realtime
- On task move → broadcast `task.moved` payload over FunnelChannel
- On stage reorder → broadcast `stages.reordered`
- Frontend reconciles: optimistic update + server confirm

---

## Phase 3.3 — Polish (later)

- Empty states per column (illustration + copy)
- Skeleton loaders
- Keyboard shortcuts (j/k navigate cards, e edit, # change priority)
- Card animations (enter/leave, position transitions)
- Filter bar: priority, assignee, label, due-range, text search
- Bulk actions (multi-select + move/delete/assign)
- Mobile: column swiper view

---

## Phase 3.4 — Automations (later)

Implement 5 toggles as background jobs hooked into existing events:
- `auto_create_task_for_new_conversation` → ConversationCreatedListener → enqueue Kanban::CreateTaskJob
- `auto_assign_task_to_agent` → ConversationAssigneeChangedListener
- `sync_task_conversation_assignees` → bidirectional sync via concerns
- `auto_resolve_conversation_on_task_close` → KanbanTask after_update on stage change to status_type=won/lost
- `auto_win_task_on_conversation_resolve` → ConversationResolvedListener

Also extend `AutomationRule` event_name enum: `task_created`, `task_updated`, `task_stage_changed` for custom automations.

---

## Phase 3.5 — Analytics (later)

- Time per stage (KanbanTaskStageHistory table — log each move with timestamp)
- Funnel conversion rate (count of won tasks / total entered)
- Avg cycle time
- Agent leaderboard (tasks closed per agent per period)
- Reports tab inside funnel settings

---

## Outstanding from earlier phases (not Phase 3)

- Fix ESLint job in CI (currently broken/skipped)
- Rebrand "Howdy, Welcome to Chatwoot" string → use `replaceInstallationName` from `useBranding`
- Cloudflare DNS for Mailgun (MX/TXT/CNAME records)
- Rotate exposed credentials (anything that leaked during deploy debugging)

---

## Local environment caveats

- Local Ruby is 2.6, project needs 3.4.4 — `bundle exec rubocop` / `rspec` won't run locally without rbenv install.
- All syntax validation done via `/usr/bin/ruby -c` per file + manual line-length check (`awk 'length>150'`) — relies on CI for full RuboCop + RSpec pass.
- `gh` CLI NOT installed — use WebFetch on `https://github.com/EuKennedy/UniverZAP/actions` for build status.
- ScheduleWakeup at 18:37 today was set before pause request — if it fires, future-self should see this file and the pause message in transcript and act accordingly (poll once, report, then halt unless user re-prompts).

---

## Repo paths cheat sheet

- Project root: `/Users/OPERACOES/Downloads/chat-univerzap/univerzap`
- Global CLAUDE.md: `/Users/OPERACOES/.claude/CLAUDE.md`
- Project CLAUDE.md: `/Users/OPERACOES/Downloads/chat-univerzap/univerzap/CLAUDE.md`
- GHCR registry: `https://github.com/EuKennedy/UniverZAP/pkgs/container/univerzap`
- Staging URL: `https://staging.univerzap.cloud`
