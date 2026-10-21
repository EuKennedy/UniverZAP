<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useScheduledMessages } from 'dashboard/composables/useScheduledMessages';
import ScheduleMessageDialog from './ScheduleMessageDialog.vue';

// "Mensagem agendada para amanhã, 09:00", logo acima do composer. Mostra o
// que está pendente (com editar/cancelar) e, por 24h, o que falhou ou foi
// cancelado sozinho — o atendente precisa saber que o lembrete não saiu
// porque a cliente respondeu antes.
const RECENT_WINDOW = 24 * 60 * 60 * 1000;
const AUTO_REASONS = ['customer_replied', 'opted_out', 'sequence_disabled'];

const { t, locale } = useI18n();

const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => currentChat.value?.id);
const { items, pending, fetch, cancel } = useScheduledMessages(conversationId);

const dialogRef = ref(null);
const isExpanded = ref(false);

const recentIssues = computed(() =>
  items.value.filter(
    item =>
      (item.status === 'failed' ||
        (item.status === 'cancelled' &&
          AUTO_REASONS.includes(item.cancel_reason))) &&
      Date.now() - new Date(item.updated_at).getTime() < RECENT_WINDOW
  )
);
const visiblePending = computed(() =>
  isExpanded.value ? pending.value : pending.value.slice(0, 1)
);

const formatWhen = iso =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

const issueText = item =>
  item.status === 'failed'
    ? t('SCHEDULED_MESSAGES.BANNER.FAILED', { error: item.error || '' })
    : t(
        `SCHEDULED_MESSAGES.BANNER.CANCELLED.${item.cancel_reason.toUpperCase()}`
      );

const refresh = () => fetch().catch(() => {});

const edit = item => dialogRef.value?.open({ scheduled: item });

const cancelItem = async item => {
  try {
    await cancel(item.id);
    useAlert(t('SCHEDULED_MESSAGES.BANNER.CANCELLED_OK'));
  } catch (error) {
    useAlert(t('SCHEDULED_MESSAGES.BANNER.CANCEL_ERROR'));
  }
};

watch(
  conversationId,
  id => {
    isExpanded.value = false;
    if (id) refresh();
  },
  { immediate: true }
);

// A cliente escreveu: o backend pode ter cancelado o agendado. Recarrega
// quando chega mensagem nova dela nesta conversa.
const lastIncomingId = computed(() => {
  const messages = currentChat.value?.messages || [];
  const incoming = messages.filter(message => message.message_type === 0);
  return incoming.length ? incoming[incoming.length - 1].id : null;
});
watch(lastIncomingId, (id, previous) => {
  if (id && previous && id !== previous && pending.value.length) {
    setTimeout(refresh, 1500);
  }
});
</script>

<template>
  <div
    class="flex flex-col gap-1 mx-2 empty:hidden"
    data-testid="scheduled-messages-banner"
  >
    <div
      v-for="item in visiblePending"
      :key="item.id"
      class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-n-teal-2 border border-n-teal-4"
      data-testid="scheduled-message-pending"
    >
      <span class="i-lucide-calendar-clock size-4 shrink-0 text-n-teal-11" />
      <div class="flex flex-col flex-1 min-w-0">
        <span class="text-xs font-medium text-n-slate-12">
          {{
            t('SCHEDULED_MESSAGES.BANNER.PENDING', {
              when: formatWhen(item.send_at),
            })
          }}
          <span
            v-if="item.sequence_name"
            class="font-normal text-n-slate-11 before:content-['·'] before:mx-1"
          >
            {{ item.sequence_name }}
          </span>
        </span>
        <span
          class="text-[11px] text-n-slate-11 truncate"
          :title="item.content"
        >
          {{ item.content }}
        </span>
      </div>
      <button
        v-if="pending.length > 1 && !isExpanded"
        type="button"
        class="shrink-0 text-[11px] text-n-teal-11 hover:underline"
        @click="isExpanded = true"
      >
        {{ t('SCHEDULED_MESSAGES.BANNER.MORE', { count: pending.length - 1 }) }}
      </button>
      <NextButton
        v-tooltip.top="t('SCHEDULED_MESSAGES.BANNER.EDIT')"
        icon="i-lucide-pencil"
        slate
        ghost
        xs
        data-testid="scheduled-message-edit"
        @click="edit(item)"
      />
      <NextButton
        v-tooltip.top="t('SCHEDULED_MESSAGES.BANNER.CANCEL')"
        icon="i-lucide-x"
        ruby
        ghost
        xs
        data-testid="scheduled-message-cancel"
        @click="cancelItem(item)"
      />
    </div>
    <div
      v-for="item in recentIssues"
      :key="`issue-${item.id}`"
      class="flex items-center gap-2 px-3 py-1.5 rounded-lg"
      :class="
        item.status === 'failed'
          ? 'bg-n-ruby-2 text-n-ruby-11'
          : 'bg-n-alpha-1 text-n-slate-11'
      "
      data-testid="scheduled-message-issue"
    >
      <span
        class="size-4 shrink-0"
        :class="
          item.status === 'failed' ? 'i-lucide-circle-alert' : 'i-lucide-ban'
        "
      />
      <span class="text-[11px] truncate" :title="item.content">
        {{ issueText(item) }}
        <span class="before:content-['—'] before:mx-1">{{ item.content }}</span>
      </span>
    </div>
    <ScheduleMessageDialog
      v-if="conversationId"
      ref="dialogRef"
      :conversation-id="conversationId"
      :contact="currentChat?.meta?.sender || {}"
      :conversation="currentChat || {}"
    />
  </div>
</template>
