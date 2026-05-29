import { frontendURL } from 'dashboard/helper/URLHelper';

import TasksIndex from './TasksIndex.vue';

const baseMeta = {
  permissions: ['administrator', 'agent'],
};

const tasksRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/tasks'),
      name: 'tasks',
      meta: baseMeta,
      component: TasksIndex,
    },
  ],
};

export default tasksRoutes;
