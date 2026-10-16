// UniverZAP: "Canais" in the sidebar is grouped. Every inbox lands in its
// explicit group (inbox_group_id), else in the group of its kind; a kind
// nobody created a group for gets a default one (id null), named after it.

// Also the order of the default groups.
export const CHANNEL_KINDS = [
  'whatsapp',
  'instagram',
  'facebook',
  'email',
  'website',
  'telegram',
  'line',
  'sms',
  'tiktok',
  'twitter',
  'api',
];

const KIND_ICONS = {
  whatsapp: 'i-woot-whatsapp',
  instagram: 'i-woot-instagram',
  facebook: 'i-woot-messenger',
  email: 'i-woot-mail',
  website: 'i-woot-website',
  telegram: 'i-woot-telegram',
  line: 'i-woot-line',
  sms: 'i-woot-sms',
  tiktok: 'i-woot-tiktok',
  twitter: 'i-woot-x',
  api: 'i-woot-api',
};

// Custom groups (no kind) come after the default ones.
export const CUSTOM_GROUP_POSITION = 100;

// The same reading of an inbox as the channel icon (useChannelIcon): WAHA and
// Twilio WhatsApp inboxes are WhatsApp.
export const inboxKind = inbox => {
  const { channel_type: type, medium } = inbox;
  switch (type) {
    case 'Channel::Whatsapp':
      return 'whatsapp';
    case 'Channel::TwilioSms':
      return medium === 'whatsapp' ? 'whatsapp' : 'sms';
    case 'Channel::Api':
      return medium === 'whatsapp' ||
        inbox.additional_attributes?.source === 'waha'
        ? 'whatsapp'
        : 'api';
    case 'Channel::Instagram':
      return 'instagram';
    case 'Channel::FacebookPage':
      return 'facebook';
    case 'Channel::Email':
      return 'email';
    case 'Channel::WebWidget':
      return 'website';
    case 'Channel::Telegram':
      return 'telegram';
    case 'Channel::Line':
      return 'line';
    case 'Channel::Sms':
      return 'sms';
    case 'Channel::Tiktok':
      return 'tiktok';
    case 'Channel::TwitterProfile':
      return 'twitter';
    default:
      return 'api';
  }
};

export const kindPosition = kind => CHANNEL_KINDS.indexOf(kind);

// [{ key, id, kind, name, position, inboxes }], ordered. Groups without
// inboxes are left out unless `includeEmpty` (the settings screen, where an
// empty group is still somewhere to move an inbox to).
export const groupInboxes = (
  inboxes,
  groups,
  { includeEmpty = false } = {}
) => {
  const byId = new Map(groups.map(group => [group.id, group]));
  const byKind = new Map(
    groups.filter(group => group.kind).map(group => [group.kind, group])
  );
  const buckets = new Map();

  const bucketFor = (group, kind) => {
    const key = group ? `group-${group.id}` : `kind-${kind}`;
    if (!buckets.has(key)) {
      buckets.set(key, {
        key,
        id: group?.id ?? null,
        kind: group ? group.kind : kind,
        name: group?.name ?? null,
        position: group ? group.position : kindPosition(kind),
        inboxes: [],
      });
    }
    return buckets.get(key);
  };

  if (includeEmpty) groups.forEach(group => bucketFor(group, group.kind));
  inboxes.forEach(inbox => {
    const kind = inboxKind(inbox);
    const group = byId.get(inbox.inbox_group_id) || byKind.get(kind);
    bucketFor(group, kind).inboxes.push(inbox);
  });

  return [...buckets.values()].sort(
    (a, b) =>
      a.position - b.position || (a.name || '').localeCompare(b.name || '')
  );
};

export const channelGroupLabel = (group, t) =>
  group.name || t(`SIDEBAR.CHANNEL_GROUPS.KINDS.${group.kind}`);

export const channelGroupIcon = group =>
  KIND_ICONS[group.kind] || 'i-lucide-folder';
