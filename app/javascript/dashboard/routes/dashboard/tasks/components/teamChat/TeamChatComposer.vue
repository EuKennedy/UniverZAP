<script setup>
import { ref, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  channelName: { type: String, default: '' },
  isSending: { type: Boolean, default: false },
});

const emit = defineEmits(['send']);

const { t } = useI18n();

const content = ref('');
const textareaRef = ref(null);

// Auto-grow the textarea up to a ceiling so multi-line drafts are visible
// without the composer eating the whole panel.
const MAX_HEIGHT = 180;
const autoGrow = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, MAX_HEIGHT)}px`;
};

watch(content, () => nextTick(autoGrow));

const send = () => {
  const value = content.value.trim();
  if (!value || props.isSending) return;
  emit('send', value);
  content.value = '';
  nextTick(() => {
    autoGrow();
    textareaRef.value?.focus();
  });
};

// Enter sends; Shift+Enter inserts a newline (Slack convention).
const onKeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    send();
  }
};
</script>

<template>
  <div class="flex-shrink-0 px-4 pb-4 pt-1">
    <div
      class="flex items-end gap-2 rounded-xl border border-n-weak bg-n-background focus-within:border-n-brand transition-colors px-3 py-2"
    >
      <textarea
        ref="textareaRef"
        v-model="content"
        rows="1"
        :placeholder="
          t('TEAM_CHAT.COMPOSER.PLACEHOLDER', { channel: channelName })
        "
        class="flex-1 bg-transparent text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none resize-none leading-relaxed max-h-[180px]"
        @keydown="onKeydown"
      />
      <button
        type="button"
        class="inline-flex items-center justify-center size-8 rounded-lg bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-sm transition-all hover:shadow-md disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer shrink-0"
        :disabled="!content.trim() || isSending"
        :aria-label="t('TEAM_CHAT.COMPOSER.SEND')"
        @click="send"
      >
        <Icon
          :icon="isSending ? 'i-lucide-loader-circle' : 'i-lucide-send'"
          class="size-4"
          :class="{ 'animate-spin': isSending }"
        />
      </button>
    </div>
    <p class="text-[10.5px] text-n-slate-10 mt-1.5 px-1">
      {{ t('TEAM_CHAT.COMPOSER.HINT') }}
    </p>
  </div>
</template>
