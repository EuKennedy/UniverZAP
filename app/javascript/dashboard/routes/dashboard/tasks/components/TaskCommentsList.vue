<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

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
      class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 ring-1 ring-n-weak"
      @submit.prevent="submit"
    >
      <textarea
        v-model="draft"
        rows="2"
        :placeholder="t('TASKS.DETAIL.COMMENTS.INPUT_PLACEHOLDER')"
        class="w-full bg-transparent outline-none resize-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
      />
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
