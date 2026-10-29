// How each WooCommerce order status looks on the customer sheet: a colour
// family (the same tints as the rest of the panel) and an icon, so an agent
// reads the history by colour before reading a word.
//
// Stores often run plugins with their own statuses, prefixed by the plugin
// (`uvf-shipped`, `wc-delivered`): the prefix is dropped to find the meaning,
// and anything still unknown is shown as plain words instead of a slug.
const STATUSES = {
  pending: { tone: 'amber', icon: 'i-lucide-clock', key: 'PENDING' },
  'on-hold': { tone: 'amber', icon: 'i-lucide-hourglass', key: 'ON_HOLD' },
  processing: { tone: 'teal', icon: 'i-lucide-badge-check', key: 'PROCESSING' },
  completed: { tone: 'iris', icon: 'i-lucide-truck', key: 'COMPLETED' },
  shipped: { tone: 'iris', icon: 'i-lucide-truck', key: 'COMPLETED' },
  delivered: {
    tone: 'violet',
    icon: 'i-lucide-package-check',
    key: 'DELIVERED',
  },
  failed: { tone: 'ruby', icon: 'i-lucide-circle-x', key: 'FAILED' },
  cancelled: { tone: 'slate', icon: 'i-lucide-ban', key: 'CANCELLED' },
  refunded: { tone: 'ruby', icon: 'i-lucide-undo-2', key: 'REFUNDED' },
};

const UNKNOWN = { tone: 'slate', icon: 'i-lucide-package', key: null };

// Full class names, so Tailwind keeps them in the build.
export const TONES = {
  amber: { tile: 'bg-n-amber-3 text-n-amber-11', text: 'text-n-amber-11' },
  teal: { tile: 'bg-n-teal-3 text-n-teal-11', text: 'text-n-teal-11' },
  iris: { tile: 'bg-n-iris-3 text-n-iris-11', text: 'text-n-iris-11' },
  violet: { tile: 'bg-n-violet-3 text-n-violet-11', text: 'text-n-violet-11' },
  ruby: { tile: 'bg-n-ruby-3 text-n-ruby-11', text: 'text-n-ruby-11' },
  slate: { tile: 'bg-n-slate-3 text-n-slate-11', text: 'text-n-slate-11' },
};

export const IN_PROGRESS = ['pending', 'on-hold', 'processing'];

const humanize = slug => {
  const words = slug.replace(/[-_]+/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
};

export const orderStatus = (status, t) => {
  const plain = (status || '').replace(/^[a-z]{2,4}-(?=[a-z])/, '');
  const meta = STATUSES[status] || STATUSES[plain] || UNKNOWN;
  return {
    ...meta,
    ...TONES[meta.tone],
    label: meta.key ? t(`STORE_ORDERS.STATUS.${meta.key}`) : humanize(plain),
  };
};
