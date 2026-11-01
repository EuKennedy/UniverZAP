import { frontendURL } from 'dashboard/helper/URLHelper.js';

// As campanhas nativas deram lugar às Campanhas de disparo: link salvo cai lá.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/campaigns/:rest(.*)*'),
      redirect: to => ({
        name: 'broadcasts_index',
        params: { accountId: to.params.accountId },
      }),
    },
  ],
};
