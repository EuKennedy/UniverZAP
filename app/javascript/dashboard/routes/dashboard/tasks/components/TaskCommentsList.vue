<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  comments: {
    type: Array,
    default: () => [],
  },
  isSubmitting: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const draft = ref('');
const inputRef = ref(null);
const showMention = ref(false);
const mentionQuery = ref('');
const mentionAnchor = ref(0);
const agents = useMapGetter('agents/getAgents');

const filteredAgents = computed(() => {
  const term = mentionQuery.value.trim().toLowerCase();
  const list = agents.value || [];
  if (!term) return list.slice(0, 6);
  return list
    .filter(
      a =>
        (a.name || '').toLowerCase().includes(term) ||
        (a.email || '').toLowerCase().includes(term)
    )
    .slice(0, 6);
});

const onDraftInput = event => {
  const value = event.target.value;
  draft.value = value;
  const caret = event.target.selectionStart || 0;
  const upToCaret = value.slice(0, caret);
  const match = upToCaret.match(/@(\w*)$/);
  if (match) {
    showMention.value = true;
    mentionQuery.value = match[1] || '';
    mentionAnchor.value = caret - match[0].length;
  } else {
    showMention.value = false;
  }
};

const insertMention = agent => {
  const before = draft.value.slice(0, mentionAnchor.value);
  const afterStart = mentionAnchor.value + mentionQuery.value.length + 1;
  const after = draft.value.slice(afterStart);
  const sanitized = (agent.name || '').replace(/\s+/g, '_');
  const inserted = `${before}@${sanitized} ${after}`;
  draft.value = inserted;
  showMention.value = false;
  mentionQuery.value = '';
  nextTick(() => inputRef.value?.focus());
};

// Backend serializes timestamps as unix epoch (seconds).
const dateFormatter = new Intl.DateTimeFormat(undefined, {
  day: '2-digit',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
});

const formatTimestamp = ts => {
  if (!ts) return '';
  const ms = typeof ts === 'number' ? ts * 1000 : Date.parse(ts);
  if (Number.isNaN(ms)) return '';
  return dateFormatter.format(new Date(ms));
};

const renderedBody = source =>
  typeof source === 'string'
    ? source
    : source?.text || JSON.stringify(source || '');

const canSubmit = computed(() => draft.value.trim().length > 0);

const submit = () => {
  if (!canSubmit.value) return;
  emit('submit', { text: draft.value.trim() });
  draft.value = '';
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <ul v-if="comments.length" class="flex flex-col gap-3 list-none m-0">
      <li
        v-for="comment in comments"
        :key="comment.id"
        class="flex gap-3 p-3 rounded-xl bg-n-alpha-1 ring-1 ring-n-weak"
      >
        <Avatar
          :name="comment.user?.name || 'User'"
          :src="comment.user?.avatar_url"
          :size="28"
          rounded-full
        />
        <div class="flex flex-col gap-1 min-w-0 flex-1">
          <div class="flex items-baseline gap-2">
            <span class="text-sm font-medium text-n-slate-12 truncate">
              {{ comment.user?.name }}
            </span>
            <span class="text-[11px] text-n-slate-10 tabular-nums">
              {{ formatTimestamp(comment.created_at) }}
            </span>
          </div>
          <p class="text-sm text-n-slate-11 whitespace-pre-wrap break-words">
            {{ renderedBody(comment.body) }}
          </p>
        </div>
      </li>
    </ul>
    <p v-else class="text-sm text-n-slate-10 text-center py-6">
      {{ t('TASKS.DETAIL.COMMENTS.EMPTY') }}
    </p>

    <form
      class="relative flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 ring-1 ring-n-weak"
      data-test-id="task-comment-form"
      @submit.prevent="submit"
    >
      <textarea
        ref="inputRef"
        :value="draft"
        rows="2"
        :placeholder="t('TASKS.DETAIL.COMMENTS.INPUT_PLACEHOLDER')"
        class="w-full bg-transparent outline-none resize-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
        data-test-id="task-comment-input"
        @input="onDraftInput"
      />
      <ul
        v-if="showMention && filteredAgents.length"
        class="absolute bottom-full left-3 right-3 mb-2 max-h-60 overflow-y-auto rounded-xl bg-n-solid-1 ring-1 ring-n-weak shadow-xl list-none m-0 p-1"
        data-test-id="task-comment-mention-popover"
      >
        <li v-for="agent in filteredAgents" :key="agent.id">
          <button
            type="button"
            class="flex w-full items-center gap-2 px-2 py-1.5 rounded-md hover:bg-n-alpha-1 text-left"
            :data-test-id="`task-comment-mention-${agent.id}`"
            @click="insertMention(agent)"
          >
            <Avatar :name="agent.name" :src="agent.thumbnail" :size="22" />
            <span class="text-sm text-n-slate-12 truncate">
              {{ agent.name }}
            </span>
          </button>
        </li>
      </ul>
      <div class="flex justify-end">
        <Button
          type="submit"
          :label="t('TASKS.DETAIL.COMMENTS.POST')"
          size="sm"
          solid
          blue
          :disabled="!canSubmit || isSubmitting"
          :is-loading="isSubmitting"
        />
      </div>
    </form>
  </div>
</template>
