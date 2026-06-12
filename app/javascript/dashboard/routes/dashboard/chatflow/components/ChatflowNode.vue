<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';

// Custom Vue Flow node: one card = one "etapa". The target handle (left) is
// where an incoming edge lands. Source handles (right) are the connection
// POINTS the operator drags to the next card — a single `default` point for
// linear steps, or one point per option on a SAC menu so each choice routes
// independently. The handle `id` is persisted as the edge `source_handle`.
const props = defineProps({
  data: { type: Object, required: true },
  selected: { type: Boolean, default: false },
});

const emit = defineEmits(['delete']);

const { t } = useI18n();

const KIND_META = {
  send_message: { icon: 'i-lucide-message-square', tone: 'teal' },
  send_audio: { icon: 'i-lucide-mic', tone: 'violet', source: 'default' },
  send_media: { icon: 'i-lucide-image', tone: 'blue' },
  menu: { icon: 'i-lucide-list-tree', tone: 'amber' },
  set_label: { icon: 'i-lucide-tag', tone: 'iris' },
  end_flow: { icon: 'i-lucide-flag', tone: 'ruby' },
};

const kind = computed(() => props.data.kind);
const meta = computed(() => KIND_META[kind.value] || KIND_META.send_message);
const isMenu = computed(() => kind.value === 'menu');
const isEnd = computed(() => kind.value === 'end_flow');

const options = computed(() =>
  isMenu.value ? props.data.config?.options || [] : []
);

const title = computed(
  () => props.data.name || t(`CHATFLOW.NODE.KIND.${kind.value.toUpperCase()}`)
);

const summary = computed(() => {
  const config = props.data.config || {};
  if (isMenu.value) return config.text || t('CHATFLOW.NODE.MENU_EMPTY');
  if (kind.value === 'send_message') return config.text || '';
  if (kind.value === 'send_audio') return t('CHATFLOW.NODE.AUDIO_SUMMARY');
  if (kind.value === 'send_media')
    return config.caption || t('CHATFLOW.NODE.MEDIA_SUMMARY');
  if (kind.value === 'set_label') return t('CHATFLOW.NODE.LABEL_SUMMARY');
  if (isEnd.value) return t('CHATFLOW.NODE.END_SUMMARY');
  return '';
});

const toneClass = computed(
  () =>
    ({
      teal: 'bg-n-teal-3 text-n-teal-11',
      violet: 'bg-n-violet-3 text-n-violet-11',
      blue: 'bg-n-blue-3 text-n-blue-11',
      amber: 'bg-n-amber-3 text-n-amber-11',
      iris: 'bg-n-iris-3 text-n-iris-11',
      ruby: 'bg-n-ruby-3 text-n-ruby-11',
    })[meta.value.tone]
);
</script>

<template>
  <div
    class="group relative w-64 rounded-2xl border bg-n-solid-1 shadow-sm transition-all"
    :class="
      selected
        ? 'border-n-teal-7 shadow-md ring-1 ring-n-teal-6/40'
        : 'border-n-weak hover:border-n-slate-6'
    "
  >
    <!-- Delete affordance (hover) -->
    <button
      type="button"
      class="absolute -top-2.5 -right-2.5 z-10 inline-flex items-center justify-center size-6 rounded-full bg-n-solid-2 text-n-slate-11 ring-1 ring-n-weak shadow-sm opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer hover:bg-n-ruby-9 hover:text-white"
      :aria-label="t('CHATFLOW.NODE.DELETE')"
      :title="t('CHATFLOW.NODE.DELETE')"
      @click.stop="emit('delete')"
    >
      <fluent-icon icon="delete" size="13" />
    </button>

    <!-- Entry point -->
    <Handle
      type="target"
      :position="Position.Left"
      class="!size-3 !bg-n-slate-8 !border-2 !border-n-solid-1"
    />

    <div class="flex items-center gap-2.5 px-3.5 pt-3.5">
      <span
        class="flex items-center justify-center size-8 rounded-lg shrink-0"
        :class="toneClass"
      >
        <fluent-icon :icon="meta.icon.replace('i-lucide-', '')" size="16" />
      </span>
      <div class="flex flex-col min-w-0">
        <p class="text-sm font-semibold text-n-slate-12 m-0 truncate">
          {{ title }}
        </p>
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10 m-0">
          {{ t(`CHATFLOW.NODE.KIND.${kind.toUpperCase()}`) }}
        </p>
      </div>
    </div>

    <p
      v-if="summary"
      class="px-3.5 pt-2 pb-3 text-xs text-n-slate-11 m-0 line-clamp-3 whitespace-pre-line"
    >
      {{ summary }}
    </p>

    <!-- SAC menu: one connection point per selectable option -->
    <div v-if="isMenu" class="flex flex-col border-t border-n-weak">
      <div
        v-for="(opt, index) in options"
        :key="opt.value || index"
        class="relative flex items-center gap-2 px-3.5 py-2 text-xs text-n-slate-12 border-b border-n-weak last:border-b-0"
      >
        <span
          class="flex items-center justify-center size-5 rounded-md bg-n-alpha-2 text-[10px] font-bold text-n-slate-11"
        >
          {{ index + 1 }}
        </span>
        <span class="truncate">{{
          opt.label || t('CHATFLOW.NODE.OPTION_EMPTY')
        }}</span>
        <Handle
          :id="String(opt.value)"
          type="source"
          :position="Position.Right"
          class="!size-3 !bg-n-amber-8 !border-2 !border-n-solid-1"
        />
      </div>
    </div>

    <!-- Linear nodes: single forward point -->
    <Handle
      v-else-if="!isEnd"
      id="default"
      type="source"
      :position="Position.Right"
      class="!size-3 !bg-n-teal-8 !border-2 !border-n-solid-1"
    />
  </div>
</template>
