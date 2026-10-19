import InboxMembersAPI from '../../api/inboxMembers';

export const actions = {
  get(_, { inboxId }) {
    return InboxMembersAPI.show(inboxId);
  },
  create(_, { inboxId, agentList, capacities }) {
    return InboxMembersAPI.update({ inboxId, agentList, capacities });
  },
};

export default {
  namespaced: true,
  actions,
};
