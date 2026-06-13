import { frontendURL } from 'dashboard/helper/URLHelper';

import BroadcastsRouteView from './pages/BroadcastsRouteView.vue';
import BroadcastsIndex from './pages/BroadcastsIndex.vue';
import BroadcastComposer from './pages/BroadcastComposer.vue';

const baseMeta = {
  permissions: ['administrator'],
};

const broadcastsRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/broadcasts'),
      component: BroadcastsRouteView,
      children: [
        {
          path: '',
          name: 'broadcasts_index',
          meta: baseMeta,
          component: BroadcastsIndex,
        },
        {
          path: ':broadcastId',
          name: 'broadcasts_show',
          meta: baseMeta,
          component: BroadcastComposer,
          props: true,
        },
      ],
    },
  ],
};

export default broadcastsRoutes;
