<script setup>
import { computed, ref, watch, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Icon from 'next/icon/Icon.vue';
import TeamChatMessage from './TeamChatMessage.vue';
import TeamChatComposer from './TeamChatComposer.vue';

const props = defineProps({
  channel: { type: Object, default: null },
});

const emit = defineEmits(['edit-channel', 'archive-channel']);

const { t, locale } = useI18n();
const store = useStore();

const uiFlags = useMapGetter('teamChat/getUiFlags');
const currentUser = useMapGetter('getCurrentUser');

const scrollRef = ref(null);

const messages = computed(() =>
  props.channel ? store.getters['teamChat/getMessages'](props.channel.id) : []
);
const hasMore = computed(() =>
  props.channel ? store.getters['teamChat/hasMore'](props.channel.id) : false
);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');

// 5-minute grouping window + same author collapses the avatar/name header.
const GROUP_WINDOW = 5 * 60;
const dayKey = ts => new Date(ts * 1000).toDateString();

const formatDay = ts => {
  const date = new Date(ts * 1000);
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  if (date.toDateString() === today.toDateString()) {
    return t('TEAM_CHAT.PANEL.TODAY');
  }
  if (date.toDateString() === yesterday.toDateString()) {
    return t('TEAM_CHAT.PANEL.YESTERDAY');
  }
  // `pt_BR` → `pt-BR`: Intl rejects the underscore form with a
  // RangeError that would blank the whole message list.
  const intlLocale = (locale.value || 'pt-BR').replace('_', '-');
  return new Intl.DateTimeFormat(intlLocale, {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(date);
};

// Decorate each message with `grouped` + an optional `dayLabel` divider so
// the template stays declarative.
const decorated = computed(() => {
  const list = messages.value;
  return list.map((msg, idx) => {
    const prev = list[idx - 1];
    const newDay = !prev || dayKey(prev.created_at) !== dayKey(msg.created_at);
    const grouped =
      !newDay &&
      prev &&
      prev.user?.id === msg.user?.id &&
      msg.created_at - prev.created_at < GROUP_WINDOW;
    return {
      msg,
      grouped,
      dayLabel: newDay ? formatDay(msg.created_at) : null,
    };
  });
});

const scrollToBottom = async () => {
  await nextTick();
  const el = scrollRef.value;
  if (el) el.scrollTop = el.scrollHeight;
};

// Keep pinned to the newest message when the active channel's message list
// grows (initial load + incoming realtime). We don't fight the user if
// they've scrolled up to read history — only autoscroll when near bottom.
watch(
  () => messages.value.length,
  async (next, prev) => {
    const el = scrollRef.value;
    const nearBottom =
      !el || el.scrollHeight - el.scrollTop - el.clientHeight < 160;
    if (next > (prev || 0) && nearBottom) await scrollToBottom();
  }
);

watch(
  () => props.channel?.id,
  () => scrollToBottom()
);

onMounted(scrollToBottom);

const onScroll = async () => {
  const el = scrollRef.value;
  if (!el || el.scrollTop > 40 || !hasMore.value) return;
  if (uiFlags.value.isFetchingMessages) return;
  const prevHeight = el.scrollHeight;
  await store.dispatch('teamChat/loadOlderMessages', props.channel.id);
  // Preserve scroll position after prepending older messages.
  await nextTick();
  el.scrollTop = el.scrollHeight - prevHeight;
};

const handleSend = async content => {
  try {
    await store.dispatch('teamChat/sendMessage', {
      channelId: props.channel.id,
      content,
    });
  } catch (error) {
    useAlert(error?.message || t('TEAM_CHAT.PANEL.SEND_ERROR'));
  }
};

const handleEdit = async ({ messageId, content }) => {
  try {
    await store.dispatch('teamChat/editMessage', {
      channelId: props.channel.id,
      messageId,
      content,
    });
  } catch (error) {
    useAlert(error?.message || t('TEAM_CHAT.PANEL.SEND_ERROR'));
  }
};

const handleDelete = async message => {
  if (!window.confirm(t('TEAM_CHAT.MESSAGE.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('teamChat/deleteMessage', {
      channelId: props.channel.id,
      messageId: message.id,
    });
  } catch (error) {
    useAlert(error?.message || t('TEAM_CHAT.PANEL.SEND_ERROR'));
  }
};
</script>

<template>
  <section v-if="channel" class="flex-1 flex flex-col min-w-0 h-full">
    <header
      class="flex-shrink-0 flex items-center justify-between gap-3 px-5 h-14 border-b border-n-weak"
    >
      <div class="flex items-center gap-2 min-w-0">
        <Icon icon="i-lucide-hash" class="size-4 text-n-slate-10 shrink-0" />
        <h2 class="text-base font-semibold text-n-slate-12 truncate">
          {{ channel.name }}
        </h2>
        <span
          v-if="channel.description"
          class="hidden md:inline text-xs text-n-slate-10 truncate ltr:border-l rtl:border-r border-n-weak ltr:pl-2 rtl:pr-2"
        >
          {{ channel.description }}
        </span>
      </div>
      <div v-if="isAdmin" class="flex items-center gap-0.5 shrink-0">
        <button
          type="button"
          class="inline-flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 cursor-pointer transition-colors"
          :aria-label="t('TEAM_CHAT.CHANNEL.EDIT')"
          @click="emit('edit-channel', channel)"
        >
          <Icon icon="i-lucide-settings-2" class="size-4" />
        </button>
        <button
          v-if="channel.kind !== 'default'"
          type="button"
          class="inline-flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:text-n-ruby-11 hover:bg-n-alpha-2 cursor-pointer transition-colors"
          :aria-label="t('TEAM_CHAT.CHANNEL.ARCHIVE')"
          @click="emit('archive-channel', channel)"
        >
          <Icon icon="i-lucide-archive" class="size-4" />
        </button>
      </div>
    </header>

    <div ref="scrollRef" class="flex-1 overflow-y-auto py-4" @scroll="onScroll">
      <div
        v-if="uiFlags.isFetchingMessages && !messages.length"
        class="flex items-center justify-center py-10"
      >
        <Icon
          icon="i-lucide-loader-circle"
          class="size-5 animate-spin text-n-slate-10"
        />
      </div>

      <div
        v-else-if="!messages.length"
        class="flex flex-col items-center justify-center gap-3 py-16 text-center px-6"
      >
        <span
          class="inline-flex items-center justify-center size-12 rounded-2xl bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-messages-square" class="size-6" />
        </span>
        <div class="flex flex-col gap-1">
          <p class="text-sm font-semibold text-n-slate-12">
            {{ t('TEAM_CHAT.PANEL.EMPTY_TITLE', { channel: channel.name }) }}
          </p>
          <p class="text-xs text-n-slate-11 max-w-xs leading-relaxed">
            {{ t('TEAM_CHAT.PANEL.EMPTY_BODY') }}
          </p>
        </div>
      </div>

      <template v-else>
        <template v-for="entry in decorated" :key="entry.msg.id">
          <div
            v-if="entry.dayLabel"
            class="flex items-center gap-3 px-4 my-3"
            role="separator"
          >
            <span class="flex-1 h-px bg-n-weak" />
            <span
              class="text-[10.5px] font-medium uppercase tracking-wide text-n-slate-10 px-2"
            >
              {{ entry.dayLabel }}
            </span>
            <span class="flex-1 h-px bg-n-weak" />
          </div>
          <TeamChatMessage
            :message="entry.msg"
            :grouped="entry.grouped"
            @edit="handleEdit"
            @delete="handleDelete"
          />
        </template>
      </template>
    </div>

    <TeamChatComposer
      :channel-name="channel.name"
      :is-sending="uiFlags.isSending"
      @send="handleSend"
    />
  </section>

  <section
    v-else
    class="flex-1 flex items-center justify-center text-sm text-n-slate-11"
  >
    {{ t('TEAM_CHAT.PANEL.NO_CHANNEL') }}
  </section>
</template>
