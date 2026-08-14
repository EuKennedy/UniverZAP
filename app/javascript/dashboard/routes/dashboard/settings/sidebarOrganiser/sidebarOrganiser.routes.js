import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

/**
 * The route stays behind the administrator permission the rest of Settings uses,
 * and the tab itself only appears for a super admin. Neither is the real gate:
 * the API refuses anyone who is not a super admin, because this rewrites the
 * menu of every tenant on the installation.
 */
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/sidebar-organiser'),
      meta: { permissions: ['administrator'] },
      component: SettingsWrapper,
      props: {
        headerTitle: 'SIDEBAR_ORGANISER.TITLE',
        icon: 'i-lucide-list-tree',
        showNewButton: false,
      },
      children: [
        {
          path: '',
          name: 'sidebar_organiser_index',
          component: Index,
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
