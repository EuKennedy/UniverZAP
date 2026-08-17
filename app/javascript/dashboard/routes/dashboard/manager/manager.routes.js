import { frontendURL } from 'dashboard/helper/URLHelper';

import ManagerIndex from './pages/ManagerIndex.vue';

// Só administrador: aprovar aqui muda a memória do agente ou abre uma disputa
// de prompt, e rodar a análise consome crédito da conta.
const adminMeta = {
  permissions: ['administrator'],
};

const managerRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/manager'),
      name: 'ai_manager',
      meta: adminMeta,
      component: ManagerIndex,
    },
  ],
};

export default managerRoutes;
