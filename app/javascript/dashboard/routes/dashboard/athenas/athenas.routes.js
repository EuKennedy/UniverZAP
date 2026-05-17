import { frontendURL } from 'dashboard/helper/URLHelper';

import AthenasRouteView from './pages/AthenasRouteView.vue';
import AssistantsList from './pages/AssistantsList.vue';
import AssistantWizard from './pages/AssistantWizard.vue';
import AssistantEdit from './pages/AssistantEdit.vue';

const adminMeta = { permissions: ['administrator'] };

const athenasRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/athenas'),
      component: AthenasRouteView,
      children: [
        {
          path: '',
          name: 'athenas_assistants_index',
          meta: adminMeta,
          component: AssistantsList,
        },
        {
          path: 'new',
          name: 'athenas_assistant_wizard',
          meta: adminMeta,
          component: AssistantWizard,
        },
        {
          path: ':id',
          name: 'athenas_assistant_edit',
          meta: adminMeta,
          component: AssistantEdit,
          props: route => ({ id: Number(route.params.id) }),
        },
      ],
    },
  ],
};

export default athenasRoutes;
