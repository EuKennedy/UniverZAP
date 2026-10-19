import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

/**
 * Closing statuses: the account's labels flagged `closes_conversation`
 * (seeded by the vertical template — e.g. cancelado, atendimento-encerrado).
 *
 * When an account has at least one, "Resolve" asks which status applies and
 * sends it along; the backend refuses a bare resolve on such accounts.
 * Accounts without any keep the one-click resolve.
 */
export function useClosingLabels() {
  const labels = useMapGetter('labels/getLabels');

  const closingLabels = computed(() =>
    (labels.value || []).filter(label => label.closes_conversation)
  );

  const requiresClosingLabel = computed(() => closingLabels.value.length > 0);

  return { closingLabels, requiresClosingLabel };
}
