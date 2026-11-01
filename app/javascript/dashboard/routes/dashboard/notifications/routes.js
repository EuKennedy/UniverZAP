import { frontendURL } from '../../../helper/URLHelper';

// A Caixa de Entrada já é a lista de notificações: uma tela só.
export const routes = [
  {
    path: frontendURL('accounts/:accountId/notifications'),
    redirect: to => ({ name: 'inbox_view', params: to.params }),
  },
];
