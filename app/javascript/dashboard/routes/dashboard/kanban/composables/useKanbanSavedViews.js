import { computed, ref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

// Saved views ride on Account.custom_attributes.kanban_saved_views — a
// flat array of { id, name, funnel_id, filters } records. We keep them
// per-account (not per-user) so a team's curated views surface for every
// admin. Module-level refs so the dropdown and the board stay in sync.
const savedViews = ref([]);
const isPersisting = ref(false);

const generateId = () =>
  `view_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;

export function useKanbanSavedViews() {
  const { currentAccount, updateAccount } = useAccount();

  // Read straight from the Vuex-backed currentAccount whenever it changes.
  // The local ref is a write-through cache so the dropdown reacts instantly
  // before the PATCH round-trip lands.
  const allViews = computed(() => {
    const stored =
      currentAccount.value?.custom_attributes?.kanban_saved_views || [];
    return savedViews.value.length ? savedViews.value : stored;
  });

  const viewsForFunnel = funnelId =>
    allViews.value.filter(view => Number(view.funnel_id) === Number(funnelId));

  const persist = async nextList => {
    savedViews.value = nextList;
    isPersisting.value = true;
    try {
      const base = currentAccount.value?.custom_attributes || {};
      await updateAccount({
        custom_attributes: { ...base, kanban_saved_views: nextList },
      });
    } finally {
      isPersisting.value = false;
    }
  };

  const saveView = async ({ name, funnelId, filters }) => {
    const view = {
      id: generateId(),
      name: String(name).trim(),
      funnel_id: Number(funnelId),
      filters,
      created_at: Date.now(),
    };
    await persist([...(allViews.value || []), view]);
    return view;
  };

  const renameView = async (id, name) => {
    const next = allViews.value.map(view =>
      view.id === id ? { ...view, name: String(name).trim() } : view
    );
    await persist(next);
  };

  const deleteView = async id => {
    await persist(allViews.value.filter(view => view.id !== id));
  };

  return {
    allViews,
    viewsForFunnel,
    isPersisting,
    saveView,
    renameView,
    deleteView,
  };
}
