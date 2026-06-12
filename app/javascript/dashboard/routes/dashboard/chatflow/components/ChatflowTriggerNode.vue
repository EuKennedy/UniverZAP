<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';
import { useMapGetter } from 'dashboard/composables/store';

// Synthetic entry node (not backed by a ChatflowNode row). Renders the
// flow's trigger config — the single most important part: WHEN the bot
// fires. Its source handle connects to the start step, which persists as
// the chatflow's start_node_id.
const props = defineProps({
  data: { type: Object, required: true },
  selected: { type: Boolean, default: false },
});

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');

const flow = computed(() => props.data.chatflow || {});

const inboxName = computed(() => {
  const id = flow.value.inbox_id;
  if (!id) return t('CHATFLOW.TRIGGER.ALL_INBOXES');
  return (
    inboxes.value.find(i => i.id === id)?.name ||
    t('CHATFLOW.TRIGGER.ALL_INBOXES')
  );
});

const conditionText = computed(() => {
  const type = flow.value.trigger_type || 'on_first_message';
  if (type === 'keyword') {
    const kws = flow.value.trigger_config?.keywords || [];
    return kws.length
      ? t('CHATFLOW.TRIGGER.SUMMARY_KEYWORD', { keywords: kws.join(', ') })
      : t('CHATFLOW.TRIGGER.SUMMARY_KEYWORD_EMPTY');
  }
  return t(`CHATFLOW.TRIGGER.TYPE.${type.toUpperCase()}.LABEL`);
});
</script>

<template>
  <div
    class="relative w-60 rounded-2xl border bg-gradient-to-br from-n-teal-9 to-n-teal-10 shadow-lg transition-all"
    :class="selected ? 'ring-2 ring-n-teal-6 shadow-xl' : ''"
  >
    <div class="flex items-center gap-2.5 px-3.5 pt-3.5">
      <span
        class="flex items-center justify-center size-8 rounded-lg bg-white/20 text-white shrink-0"
      >
        <fluent-icon icon="flash" size="18" />
      </span>
      <div class="flex flex-col min-w-0">
        <p
          class="text-[10px] font-bold uppercase tracking-[0.16em] text-white/70 m-0"
        >
          {{ t('CHATFLOW.TRIGGER.BADGE') }}
        </p>
        <p class="text-sm font-semibold text-white m-0 truncate">
          {{ inboxName }}
        </p>
      </div>
    </div>

    <div class="px-3.5 pb-3.5 pt-2">
      <p class="text-xs text-white/85 m-0 leading-snug">
        {{ conditionText }}
      </p>
      <p
        class="mt-2 inline-flex items-center gap-1 text-[11px] font-medium text-white/70 m-0"
      >
        <fluent-icon icon="settings" size="11" />
        {{ t('CHATFLOW.TRIGGER.EDIT_HINT') }}
      </p>
    </div>

    <Handle
      id="default"
      type="source"
      :position="Position.Right"
      class="!size-3.5 !bg-white !border-2 !border-n-teal-10"
    />
  </div>
</template>
