import { frontendURL } from '../../../helper/URLHelper';

// O agente de IA daqui é o Athenas: as telas do Captain saíram e o link salvo
// cai nele.
const toAssistants = to => ({
  name: 'athenas_assistants_index',
  params: { accountId: to.params.accountId },
});

export const routes = [
  {
    path: frontendURL('accounts/:accountId/captain/:rest(.*)*'),
    redirect: toAssistants,
  },
  {
    path: frontendURL('accounts/:accountId/settings/captain'),
    redirect: toAssistants,
  },
];
