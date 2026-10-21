// Catálogo dos blocos do Chatflow: ícone, cor, grupo da paleta, configuração
// inicial e as SAÍDAS de cada um. As saídas são o contrato com o motor
// (Chatflow::EngineService): o `handle` vira o `source_handle` da ligação, e
// renomear um handle aqui desligaria fluxos já desenhados.

export const KIND_META = {
  send_message: {
    icon: 'i-lucide-message-square',
    tone: 'teal',
    group: 'messages',
  },
  send_audio: { icon: 'i-lucide-mic', tone: 'violet', group: 'messages' },
  send_media: { icon: 'i-lucide-image', tone: 'blue', group: 'messages' },
  typing: { icon: 'i-lucide-ellipsis', tone: 'slate', group: 'messages' },
  menu: { icon: 'i-lucide-list-tree', tone: 'amber', group: 'questions' },
  question: {
    icon: 'i-lucide-message-circle-question',
    tone: 'amber',
    group: 'questions',
  },
  confirmation: {
    icon: 'i-lucide-circle-check-big',
    tone: 'teal',
    group: 'questions',
  },
  send_flow: {
    icon: 'i-lucide-clipboard-list',
    tone: 'amber',
    group: 'questions',
  },
  condition: { icon: 'i-lucide-split', tone: 'iris', group: 'logic' },
  wait: { icon: 'i-lucide-hourglass', tone: 'blue', group: 'logic' },
  random_split: { icon: 'i-lucide-shuffle', tone: 'violet', group: 'logic' },
  goto_flow: {
    icon: 'i-lucide-corner-down-right',
    tone: 'iris',
    group: 'logic',
  },
  set_label: { icon: 'i-lucide-tag', tone: 'iris', group: 'actions' },
  assign_agent: { icon: 'i-lucide-user-check', tone: 'blue', group: 'actions' },
  add_to_kanban: {
    icon: 'i-lucide-kanban-square',
    tone: 'iris',
    group: 'actions',
  },
  list_action: { icon: 'i-lucide-list-plus', tone: 'teal', group: 'actions' },
  webhook: { icon: 'i-lucide-webhook', tone: 'violet', group: 'actions' },
  end_flow: { icon: 'i-lucide-flag', tone: 'ruby', group: 'actions' },
};

export const PALETTE_GROUPS = ['messages', 'questions', 'logic', 'actions'];

export const paletteFor = group =>
  Object.entries(KIND_META)
    .filter(([, meta]) => meta.group === group)
    .map(([kind, meta]) => ({ kind, icon: meta.icon }));

export const TONE_CLASSES = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  violet: 'bg-n-violet-3 text-n-violet-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  slate: 'bg-n-alpha-2 text-n-slate-11',
};

export const DEFAULT_CONFIG = {
  send_message: { text: '' },
  send_audio: {},
  send_media: { caption: '' },
  menu: { text: '', options: [] },
  // Já vem pronta para usar: a pergunta e as palavras que a maioria das pessoas
  // responde. Uma etapa de fechamento que nasce em branco é uma etapa que
  // ninguém configura direito e que solta o cliente no meio do caminho.
  confirmation: {
    text: 'Seu problema foi resolvido?',
    resolved_keywords: ['sim', 'resolveu', 'obrigado', 'valeu'],
    unresolved_keywords: ['não', 'nao resolveu', 'quero humano', 'atendente'],
    fallback_text: 'Desculpa, não entendi. Responda com Sim ou Não.',
  },
  // Texto e botão já preenchidos: um formulário sem chamada é um botão vazio
  // no WhatsApp, e a Meta recusa o envio.
  send_flow: { text: 'Toque no botão para preencher.', cta: 'Preencher' },
  set_label: { label_ids: [] },
  assign_agent: {},
  add_to_kanban: {},
  webhook: { method: 'post' },
  end_flow: { actions: {} },
  question: {
    text: '',
    field_type: 'text',
    save_to: { scope: 'contact', key: '' },
    error_text: '',
    max_attempts: 3,
  },
  condition: { match: 'all', rules: [] },
  // Esperar nasce com "se responder, encerra": o lembrete programado perde o
  // sentido quando a pessoa volta a falar.
  wait: {
    mode: 'duration',
    amount: 1,
    unit: 'hours',
    on_reply: 'stop',
    respect_window: true,
  },
  random_split: {
    branches: [
      { value: 'a', label: 'A', percent: 50 },
      { value: 'b', label: 'B', percent: 50 },
    ],
  },
  goto_flow: {},
  typing: { seconds: 3 },
  list_action: { action: 'add' },
};

export const defaultConfigFor = kind =>
  JSON.parse(JSON.stringify(DEFAULT_CONFIG[kind] || {}));

// As saídas nomeadas de um bloco, na ordem em que aparecem no cartão. Bloco
// linear tem uma só (`default`, sem rótulo); "Fim" e "Ir para outro fluxo" não
// têm nenhuma.
// Classes escritas por extenso para o Tailwind enxergar: a bolinha do rótulo e
// a da porta (com `!` para vencer o tema do Vue Flow).
const HANDLE_DOTS = {
  'bg-n-teal-9': '!bg-n-teal-9',
  'bg-n-teal-8': '!bg-n-teal-8',
  'bg-n-ruby-9': '!bg-n-ruby-9',
  'bg-n-amber-9': '!bg-n-amber-9',
  'bg-n-blue-9': '!bg-n-blue-9',
  'bg-n-violet-9': '!bg-n-violet-9',
};

export const nodeHandles = (node, t) => {
  const config = node.config || {};
  const branch = (handle, label, dot) => ({
    handle,
    label,
    dot,
    handleClass: HANDLE_DOTS[dot],
  });
  switch (node.kind) {
    case 'menu':
      return (config.options || []).map(opt =>
        branch(
          String(opt.value),
          opt.label || t('CHATFLOW.NODE.OPTION_EMPTY'),
          'bg-n-amber-9'
        )
      );
    case 'confirmation':
      return [
        branch(
          'resolved',
          t('CHATFLOW.NODE.CONFIRMATION_RESOLVED'),
          'bg-n-teal-9'
        ),
        branch(
          'unresolved',
          t('CHATFLOW.NODE.CONFIRMATION_UNRESOLVED'),
          'bg-n-ruby-9'
        ),
      ];
    case 'send_flow':
      return [
        branch('default', t('CHATFLOW.NODE.FLOW_ANSWERED'), 'bg-n-teal-9'),
        branch('fallback', t('CHATFLOW.NODE.FLOW_TYPED'), 'bg-n-amber-9'),
      ];
    case 'question':
      return [
        branch('default', t('CHATFLOW.NODE.QUESTION_VALID'), 'bg-n-teal-9'),
        branch('invalid', t('CHATFLOW.NODE.QUESTION_INVALID'), 'bg-n-ruby-9'),
      ];
    case 'condition':
      return [
        branch('true', t('CHATFLOW.NODE.CONDITION_TRUE'), 'bg-n-teal-9'),
        branch('false', t('CHATFLOW.NODE.CONDITION_FALSE'), 'bg-n-ruby-9'),
      ];
    case 'wait':
      return config.on_reply === 'branch'
        ? [
            branch('default', t('CHATFLOW.NODE.WAIT_DONE'), 'bg-n-blue-9'),
            branch('replied', t('CHATFLOW.NODE.WAIT_REPLIED'), 'bg-n-amber-9'),
          ]
        : [branch('default', null, 'bg-n-teal-8')];
    case 'random_split':
      return (config.branches || []).map(item =>
        branch(
          String(item.value),
          `${item.label || item.value} · ${Number(item.percent) || 0}%`,
          'bg-n-violet-9'
        )
      );
    case 'end_flow':
    case 'goto_flow':
      return [];
    default:
      return [branch('default', null, 'bg-n-teal-8')];
  }
};

export const hasNamedHandles = node =>
  nodeHandles(node, key => key).some(item => item.label !== null);

const UNIT_KEYS = { minutes: 'MINUTES', hours: 'HOURS', days: 'DAYS' };

// O texto curto do cartão, que diz o que a etapa faz sem abrir o painel.
export const nodeSummary = (node, t, { flows = [], lists = [] } = {}) => {
  const config = node.config || {};
  switch (node.kind) {
    case 'menu':
      return config.text || t('CHATFLOW.NODE.MENU_EMPTY');
    case 'confirmation':
      return config.text || t('CHATFLOW.NODE.CONFIRMATION_EMPTY');
    case 'send_message':
      return config.text || '';
    case 'send_flow':
      return config.text || t('CHATFLOW.NODE.FLOW_SUMMARY');
    case 'send_audio':
      return t('CHATFLOW.NODE.AUDIO_SUMMARY');
    case 'send_media':
      return config.caption || t('CHATFLOW.NODE.MEDIA_SUMMARY');
    case 'set_label':
      return t('CHATFLOW.NODE.LABEL_SUMMARY');
    case 'assign_agent':
      return t('CHATFLOW.NODE.ASSIGN_SUMMARY');
    case 'add_to_kanban':
      return t('CHATFLOW.NODE.KANBAN_SUMMARY');
    case 'webhook':
      return config.url || t('CHATFLOW.NODE.WEBHOOK_SUMMARY');
    case 'end_flow':
      return t('CHATFLOW.NODE.END_SUMMARY');
    case 'question':
      return config.text || t('CHATFLOW.NODE.QUESTION_EMPTY');
    case 'condition':
      return t('CHATFLOW.NODE.CONDITION_SUMMARY', {
        count: (config.rules || []).length,
      });
    case 'wait':
      if (config.mode === 'until') {
        return t('CHATFLOW.NODE.WAIT_UNTIL_SUMMARY', {
          date: config.until
            ? config.until.replace('T', ' ').slice(0, 16)
            : '—',
        });
      }
      return t('CHATFLOW.NODE.WAIT_SUMMARY', {
        amount: Number(config.amount) || 1,
        unit: t(`CHATFLOW.EDITOR.UNIT.${UNIT_KEYS[config.unit] || 'MINUTES'}`),
      });
    case 'random_split':
      return t('CHATFLOW.NODE.SPLIT_SUMMARY', {
        count: (config.branches || []).length,
      });
    case 'goto_flow': {
      const target = flows.find(f => f.id === config.chatflow_id);
      return target
        ? t('CHATFLOW.NODE.GOTO_SUMMARY', { name: target.name })
        : t('CHATFLOW.NODE.GOTO_EMPTY');
    }
    case 'typing':
      return t('CHATFLOW.NODE.TYPING_SUMMARY', {
        seconds: Number(config.seconds) || 3,
      });
    case 'list_action': {
      const list = lists.find(l => l.id === config.list_id);
      const key = config.action === 'remove' ? 'LIST_REMOVE' : 'LIST_ADD';
      return t(`CHATFLOW.NODE.${key}`, {
        name: list?.name || t('CHATFLOW.NODE.LIST_NONE'),
      });
    }
    default:
      return '';
  }
};

// Soma dos percentuais de um A/B — o editor avisa quando não fecha 100.
export const splitTotal = branches =>
  (branches || []).reduce((sum, b) => sum + (Number(b.percent) || 0), 0);

// Próximo valor livre para um ramo novo do A/B: a, b, c…
export const nextBranchValue = branches => {
  const used = new Set((branches || []).map(b => b.value));
  const letters = 'abcdefghij'.split('');
  return letters.find(letter => !used.has(letter)) || `r${used.size + 1}`;
};
