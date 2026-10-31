// UniverZAP: whose turn it is in a conversation — the client-side mirror of
// Message#set_conversation_activity, so a conversation moves between
// Aguardando and Aguardando cliente the moment a message arrives over the
// websocket, without waiting for the next fetch.
//
// The server's `awaiting_reply` is the truth when the list is fetched; after
// that, the newest message that counts decides: the contact's (incoming) means
// our move, ours (outgoing, or the note WAHA writes for a reply typed in the
// phone) means theirs. Activities, templates and other private notes don't
// change whose turn it is. A status that waits on the contact parks the turn:
// messages up to `turn_parked_at` no longer count (Conversation#hand_turn_to_contact).
const INCOMING = 0;
const OUTGOING = 1;
const PHONE_REPLY_NOTE = /^\s*\*?📱 (?:Enviado do|Sent from) WhatsApp\*?/;

const countsForTurn = message =>
  message.private
    ? PHONE_REPLY_NOTE.test(message.content || '')
    : [INCOMING, OUTGOING].includes(message.message_type);

export const isOurTurn = conversation => {
  const parkedAt = conversation.additional_attributes?.turn_parked_at || 0;
  const latest = (conversation.messages || [])
    .filter(message => message.created_at > parkedAt && countsForTurn(message))
    .reduce(
      (newest, message) =>
        !newest || message.created_at >= newest.created_at ? message : newest,
      null
    );
  if (!latest) return !!conversation.awaiting_reply;
  return !latest.private && latest.message_type === INCOMING;
};
