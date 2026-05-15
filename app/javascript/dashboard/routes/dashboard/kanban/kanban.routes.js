import { frontendURL } from 'dashboard/helper/URLHelper';

import KanbanRouteView from './pages/KanbanRouteView.vue';
import KanbanOverview from './pages/KanbanOverview.vue';
import KanbanBoard from './pages/KanbanBoard.vue';
import KanbanFunnelSettings from './pages/KanbanFunnelSettings.vue';

const baseMeta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

const adminMeta = {
  permissions: ['administrator'],
};

const kanbanRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/kanban'),
      component: KanbanRouteView,
      children: [
        {
          path: '',
          name: 'kanban_overview',
          meta: baseMeta,
          component: KanbanOverview,
        },
        {
          path: ':funnelId',
          name: 'kanban_board',
          meta: baseMeta,
          component: KanbanBoard,
          props: true,
        },
        {
          path: ':funnelId/task/:taskId',
          name: 'kanban_task_show',
          meta: baseMeta,
          component: KanbanBoard,
          props: true,
        },
        {
          path: ':funnelId/settings',
          name: 'kanban_funnel_settings',
          meta: adminMeta,
          component: KanbanFunnelSettings,
          props: true,
        },
      ],
    },
  ],
};

export default kanbanRoutes;
