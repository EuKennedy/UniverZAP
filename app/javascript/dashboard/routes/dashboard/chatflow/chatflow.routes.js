import { frontendURL } from 'dashboard/helper/URLHelper';

import ChatflowRouteView from './pages/ChatflowRouteView.vue';
import ChatflowIndex from './pages/ChatflowIndex.vue';
import ChatflowBuilder from './pages/ChatflowBuilder.vue';

const baseMeta = {
  permissions: ['administrator'],
};

const chatflowRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/chatflow'),
      component: ChatflowRouteView,
      children: [
        {
          path: '',
          name: 'chatflow_index',
          meta: baseMeta,
          component: ChatflowIndex,
        },
        {
          path: ':chatflowId',
          name: 'chatflow_builder',
          meta: baseMeta,
          component: ChatflowBuilder,
          props: true,
        },
      ],
    },
  ],
};

export default chatflowRoutes;
