import { frontendURL } from 'dashboard/helper/URLHelper';

import WhatsAppProfileIndex from './pages/WhatsAppProfileIndex.vue';

// Só administrador: o que se edita aqui é o perfil público da empresa e o que
// se publica sai para todos os contatos do número.
const adminMeta = {
  permissions: ['administrator'],
};

const whatsappProfileRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/whatsapp-profile'),
      name: 'whatsapp_profile',
      meta: adminMeta,
      component: WhatsAppProfileIndex,
    },
  ],
};

export default whatsappProfileRoutes;
