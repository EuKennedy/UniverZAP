import { frontendURL } from 'dashboard/helper/URLHelper';

import ContactListsRouteView from './pages/ContactListsRouteView.vue';
import ContactListsIndex from './pages/ContactListsIndex.vue';
import ContactListShow from './pages/ContactListShow.vue';

// Ver é de qualquer pessoa da conta (como os disparos); a API recusa as
// ações de administrador para agentes.
const baseMeta = {
  permissions: ['administrator', 'agent'],
};

const contactListsRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/contact-lists'),
      component: ContactListsRouteView,
      children: [
        {
          path: '',
          name: 'contact_lists_index',
          meta: baseMeta,
          component: ContactListsIndex,
        },
        {
          path: ':listId',
          name: 'contact_lists_show',
          meta: baseMeta,
          component: ContactListShow,
          props: true,
        },
      ],
    },
  ],
};

export default contactListsRoutes;
