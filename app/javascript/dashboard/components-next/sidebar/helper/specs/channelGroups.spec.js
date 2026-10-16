import { groupInboxes, inboxKind } from '../channelGroups';

const whatsapp = {
  id: 1,
  name: 'comercial4349',
  channel_type: 'Channel::Whatsapp',
};
const waha = {
  id: 2,
  name: 'suporte',
  channel_type: 'Channel::Api',
  additional_attributes: { source: 'waha' },
};
const instagram = { id: 3, name: '@liso', channel_type: 'Channel::Instagram' };
const email = { id: 4, name: 'sac', channel_type: 'Channel::Email' };

const summary = buckets =>
  buckets.map(b => [b.key, b.inboxes.map(inbox => inbox.id)]);

describe('inboxKind', () => {
  it('reads WAHA and Twilio WhatsApp inboxes as WhatsApp', () => {
    expect(inboxKind(waha)).toBe('whatsapp');
    expect(
      inboxKind({ channel_type: 'Channel::TwilioSms', medium: 'whatsapp' })
    ).toBe('whatsapp');
    expect(inboxKind({ channel_type: 'Channel::Api' })).toBe('api');
  });
});

describe('groupInboxes', () => {
  it('groups by kind, in the order of the kinds, with no groups saved', () => {
    expect(
      summary(groupInboxes([email, instagram, whatsapp, waha], []))
    ).toEqual([
      ['kind-whatsapp', [1, 2]],
      ['kind-instagram', [3]],
      ['kind-email', [4]],
    ]);
  });

  it('uses the saved group of a kind, and an explicit group over it', () => {
    const groups = [
      { id: 10, name: 'Atendimento', kind: 'whatsapp', position: 0 },
      { id: 11, name: 'Vendas', kind: null, position: 100 },
    ];
    const moved = { ...waha, inbox_group_id: 11 };
    const buckets = groupInboxes([whatsapp, moved, instagram], groups);

    expect(summary(buckets)).toEqual([
      ['group-10', [1]],
      ['kind-instagram', [3]],
      ['group-11', [2]],
    ]);
    expect(buckets[0].name).toBe('Atendimento');
  });

  it('shows empty groups only when asked', () => {
    const groups = [{ id: 11, name: 'Vendas', kind: null, position: 100 }];

    expect(summary(groupInboxes([email], groups))).toEqual([
      ['kind-email', [4]],
    ]);
    expect(
      summary(groupInboxes([email], groups, { includeEmpty: true }))
    ).toEqual([
      ['kind-email', [4]],
      ['group-11', []],
    ]);
  });
});
