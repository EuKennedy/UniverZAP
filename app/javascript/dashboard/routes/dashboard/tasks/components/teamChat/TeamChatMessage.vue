<script setup>
import { computed, ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  message: { type: Object, required: true },
  // When true the avatar + name + timestamp header is hidden — the message
  // is a follow-up from the same author within the grouping window, so it
  // reads as one continuous block (Slack/Discord style).
  grouped: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'delete']);

const { t, locale } = useI18n();
const currentUser = useMapGetter('getCurrentUser');

const isAuthor = computed(
  () => currentUser.value?.id === props.message.user?.id
);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');
const canEdit = computed(() => isAuthor.value);
const canDelete = computed(() => isAuthor.value || isAdmin.value);

const isEditing = ref(false);
const draft = ref('');
const editRef = ref(null);

// Chatwoot stores locales like `pt_BR` (underscore), but Intl needs a
// BCP-47 tag (`pt-BR`). Passing the raw value throws
// `RangeError: Invalid language tag` and takes the whole message list
// down with it — which is exactly why messages "didn't appear".
const intlLocale = computed(() => (locale.value || 'pt-BR').replace('_', '-'));

const timeLabel = computed(() => {
  const date = new Date(props.message.created_at * 1000);
  return new Intl.DateTimeFormat(intlLocale.value, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
});

const startEdit = async () => {
  draft.value = props.message.content;
  isEditing.value = true;
  await nextTick();
  editRef.value?.focus();
};

const cancelEdit = () => {
  isEditing.value = false;
  draft.value = '';
};

const submitEdit = () => {
  const content = draft.value.trim();
  if (!content || content === props.message.content) {
    cancelEdit();
    return;
  }
  emit('edit', { messageId: props.message.id, content });
  isEditing.value = false;
};
</script>

<template>
  <div
    class="group relative flex gap-3 px-4 py-0.5 hover:bg-n-alpha-1 transition-colors"
    :class="grouped ? 'mt-0' : 'mt-3'"
  >
    <!-- Gutter: avatar on the first message of a block, hover-timestamp on
         the grouped follow-ups so the column stays aligned. -->
    <div class="w-9 flex-shrink-0 flex justify-center">
      <Avatar
        v-if="!grouped"
        :src="message.user.avatar_url"
        :name="message.user.name || '?'"
        :size="36"
        rounded-full
      />
      <span
        v-else
        class="text-[10px] text-n-slate-10 opacity-0 group-hover:opacity-100 transition-opacity self-center tabular-nums"
      >
        {{ timeLabel }}
      </span>
    </div>

    <div class="flex-1 min-w-0">
      <header v-if="!grouped" class="flex items-baseline gap-2">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ message.user.name }}
        </span>
        <span class="text-[11px] text-n-slate-10 tabular-nums">
          {{ timeLabel }}
        </span>
      </header>

      <div v-if="isEditing" class="mt-1 flex flex-col gap-2">
        <textarea
          ref="editRef"
          v-model="draft"
          rows="2"
          class="w-full px-3 py-2 rounded-lg bg-n-background ring-1 ring-n-weak focus:ring-n-brand focus:outline-none text-sm text-n-slate-12 resize-none"
          @keydown.enter.exact.prevent="submitEdit"
          @keydown.esc.prevent="cancelEdit"
        />
        <div class="flex items-center gap-2 text-[11px]">
          <button
            type="button"
            class="text-n-teal-11 hover:text-n-teal-12 font-medium cursor-pointer"
            @click="submitEdit"
          >
            {{ t('TEAM_CHAT.MESSAGE.SAVE') }}
          </button>
          <button
            type="button"
            class="text-n-slate-10 hover:text-n-slate-12 cursor-pointer"
            @click="cancelEdit"
          >
            {{ t('TEAM_CHAT.MESSAGE.CANCEL') }}
          </button>
        </div>
      </div>

      <!-- whitespace-pre-wrap preserves the author's line breaks; break-words
           stops a long unbroken URL from blowing out the column. -->
      <p
        v-else
        class="text-sm text-n-slate-12 leading-relaxed whitespace-pre-wrap break-words m-0"
      >
        {{ message.content }}
        <span v-if="message.edited" class="text-[10px] text-n-slate-10 ml-1">
          {{ t('TEAM_CHAT.MESSAGE.EDITED') }}
        </span>
      </p>
    </div>

    <!-- Hover toolbar — floats top-right, only the actions the user is
         allowed to take. -->
    <div
      v-if="!isEditing && (canEdit || canDelete)"
      class="absolute top-0 ltr:right-3 rtl:left-3 -translate-y-1/2 hidden group-hover:flex items-center gap-0.5 rounded-lg border border-n-weak bg-n-surface-1 shadow-md p-0.5"
    >
      <button
        v-if="canEdit"
        type="button"
        class="inline-flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 cursor-pointer transition-colors"
        :aria-label="t('TEAM_CHAT.MESSAGE.EDIT')"
        @click="startEdit"
      >
        <Icon icon="i-lucide-pencil" class="size-3.5" />
      </button>
      <button
        v-if="canDelete"
        type="button"
        class="inline-flex items-center justify-center size-7 rounded-md text-n-slate-11 hover:text-n-ruby-11 hover:bg-n-alpha-2 cursor-pointer transition-colors"
        :aria-label="t('TEAM_CHAT.MESSAGE.DELETE')"
        @click="emit('delete', message)"
      >
        <Icon icon="i-lucide-trash-2" class="size-3.5" />
      </button>
    </div>
  </div>
</template>
