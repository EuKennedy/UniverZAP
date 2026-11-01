import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import ReportsWrapper from './components/ReportsWrapper.vue';
import Index from './Index.vue';

import AgentReportsIndex from './AgentReportsIndex.vue';
import InboxReportsIndex from './InboxReportsIndex.vue';
import TeamReportsIndex from './TeamReportsIndex.vue';
import LabelReportsIndex from './LabelReportsIndex.vue';

import AgentReportsShow from './AgentReportsShow.vue';
import InboxReportsShow from './InboxReportsShow.vue';
import TeamReportsShow from './TeamReportsShow.vue';
import LabelReportsShow from './LabelReportsShow.vue';

import CsatResponses from './CsatResponses.vue';
import AthenasReports from './AthenasReports.vue';
import LiveReports from './LiveReports.vue';
import AdLeadsReports from './AdLeadsReports.vue';
import PanelReports from './PanelReports.vue';

const meta = {
  featureFlag: FEATURE_FLAGS.REPORTS,
  permissions: ['administrator', 'report_manage'],
};

// As telas antigas por entidade viraram as visões atuais: link salvo e atalho
// continuam funcionando.
const oldReportRoutes = [
  { path: 'agent', target: 'agent_reports_index' },
  { path: 'inboxes', target: 'inbox_reports_index' },
  { path: 'label', target: 'label_reports_index' },
  { path: 'teams', target: 'team_reports_index' },
  { path: 'sla', target: 'account_overview_reports' },
].map(({ path, target }) => ({
  path,
  redirect: to => ({ name: target, params: to.params }),
}));

const revisedReportRoutes = [
  {
    path: 'agents_overview',
    name: 'agent_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentReportsIndex,
  },
  {
    path: 'agents/:id',
    name: 'agent_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentReportsShow,
  },

  {
    path: 'inboxes_overview',
    name: 'inbox_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: InboxReportsIndex,
  },
  {
    path: 'inboxes/:id',
    name: 'inbox_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: InboxReportsShow,
  },
  {
    path: 'teams_overview',
    name: 'team_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: TeamReportsIndex,
  },
  {
    path: 'teams/:id',
    name: 'team_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: TeamReportsShow,
  },
  {
    path: 'labels_overview',
    name: 'label_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelReportsIndex,
  },
  {
    path: 'labels/:id',
    name: 'label_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelReportsShow,
  },
];

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/reports'),
      component: ReportsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'account_overview_reports', params: to.params };
          },
        },
        {
          path: 'overview',
          name: 'account_overview_reports',
          meta,
          component: LiveReports,
        },
        {
          path: 'conversation',
          name: 'conversation_reports',
          meta,
          component: Index,
        },
        ...oldReportRoutes,
        ...revisedReportRoutes,
        {
          path: 'csat',
          name: 'csat_reports',
          meta,
          component: CsatResponses,
        },
        // Ocupa o lugar do relatório de bot. O bot nativo está desligado nesta
        // instalação, então aquela aba media uma coisa que não acontece, e
        // quem responde cliente de verdade aqui é o Athenas.
        {
          path: 'athenas',
          name: 'athenas_reports',
          meta,
          component: AthenasReports,
        },
        {
          path: 'ad_leads',
          name: 'ad_leads_reports',
          meta,
          component: AdLeadsReports,
        },
        // Painel gerencial: funil de anúncio, fila e atendentes num só lugar.
        {
          path: 'painel',
          name: 'panel_reports',
          meta,
          component: PanelReports,
        },
        // A rota antiga continua respondendo para não quebrar link salvo nem
        // aba deixada aberta: leva para o mesmo lugar.
        {
          path: 'bot',
          name: 'bot_reports',
          redirect: to => ({ name: 'athenas_reports', params: to.params }),
        },
      ],
    },
  ],
};
