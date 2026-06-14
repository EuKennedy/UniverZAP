import { frontendURL } from 'dashboard/helper/URLHelper';

import MetasRouteView from './pages/MetasRouteView.vue';
import MetasIndex from './pages/MetasIndex.vue';

const baseMeta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

const metasRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/metas'),
      component: MetasRouteView,
      children: [
        {
          path: '',
          name: 'metas_index',
          meta: baseMeta,
          component: MetasIndex,
        },
      ],
    },
  ],
};

export default metasRoutes;
