import { isOurTurn } from '../conversationTurn';

const msg = (message_type, created_at, extra = {}) => ({
  message_type,
  created_at,
  ...extra,
});

describe('isOurTurn', () => {
  it('trusts the server when no message is loaded', () => {
    expect(isOurTurn({ awaiting_reply: true, messages: [] })).toBe(true);
    expect(isOurTurn({ awaiting_reply: false })).toBe(false);
  });

  it('is our move when the contact wrote last, theirs when we did', () => {
    expect(
      isOurTurn({ awaiting_reply: false, messages: [msg(1, 10), msg(0, 20)] })
    ).toBe(true);
    expect(
      isOurTurn({ awaiting_reply: true, messages: [msg(0, 10), msg(1, 20)] })
    ).toBe(false);
  });

  it('ignores activities, templates and plain private notes', () => {
    const messages = [
      msg(0, 10),
      msg(2, 20),
      msg(3, 30),
      msg(1, 40, { private: true, content: 'nota interna' }),
    ];
    expect(isOurTurn({ awaiting_reply: true, messages })).toBe(true);
  });

  it('counts the note for a reply typed in the phone as ours', () => {
    const messages = [
      msg(0, 10),
      msg(1, 20, { private: true, content: '📱 Enviado do WhatsApp\nOi!' }),
    ];
    expect(isOurTurn({ awaiting_reply: true, messages })).toBe(false);
  });
});
