<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';

const props = defineProps({
  toast: {
    type: Object,
    required: true,
  },
  viewLabel: {
    type: String,
    required: true,
  },
  markReadLabel: {
    type: String,
    required: true,
  },
  dismissLabel: {
    type: String,
    required: true,
  },
  autoDismissAfterMs: {
    type: Number,
    default: 8000,
  },
});

const emit = defineEmits(['view', 'markRead', 'dismiss']);

const isMounted = ref(false);
const isHovered = ref(false);
let dismissTimer = null;

const toneClasses = computed(() => {
  // The icon chip + accent bar borrow the brand palette tokens defined
  // in tailwind.config.js so we stay in lockstep with the dark-first
  // system tones (teal/ruby/amber/slate).
  switch (props.toast.tone) {
    case 'ruby':
      return {
        icon: 'bg-n-ruby-9/15 text-n-ruby-11 ring-1 ring-n-ruby-7/40',
        border: 'border-n-ruby-7/40',
      };
    case 'amber':
      return {
        icon: 'bg-n-amber-9/15 text-n-amber-11 ring-1 ring-n-amber-7/40',
        border: 'border-n-amber-7/40',
      };
    case 'teal':
      return {
        icon: 'bg-n-teal-9/15 text-n-teal-11 ring-1 ring-n-teal-7/40',
        border: 'border-n-teal-7/40',
      };
    default:
      return {
        icon: 'bg-n-slate-9/15 text-n-slate-11 ring-1 ring-n-slate-7/40',
        border: 'border-n-teal-7/40',
      };
  }
});

const clearDismissTimer = () => {
  if (dismissTimer) {
    clearTimeout(dismissTimer);
    dismissTimer = null;
  }
};

const startDismissTimer = () => {
  clearDismissTimer();
  if (props.autoDismissAfterMs <= 0) return;
  dismissTimer = setTimeout(() => {
    emit('dismiss');
  }, props.autoDismissAfterMs);
};

const handleMouseEnter = () => {
  isHovered.value = true;
  clearDismissTimer();
};

const handleMouseLeave = () => {
  isHovered.value = false;
  startDismissTimer();
};

onMounted(() => {
  // requestAnimationFrame so the enter transition has a stable origin
  // (otherwise the element renders already at its final position).
  requestAnimationFrame(() => {
    isMounted.value = true;
  });
  startDismissTimer();
});

onBeforeUnmount(() => {
  clearDismissTimer();
});
</script>

<template>
  <div
    data-test-id="task-notification-toast"
    :data-toast-id="toast.id"
    class="rounded-2xl bg-n-surface-1/95 backdrop-blur-xl border shadow-[0_24px_70px_-20px_rgba(0,0,0,0.55)] w-96 max-w-[calc(100vw-2rem)] p-4 motion-safe:transition-all motion-safe:duration-500 ease-out"
    :class="[
      toneClasses.border,
      isMounted ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-full',
    ]"
    role="status"
    @mouseenter="handleMouseEnter"
    @mouseleave="handleMouseLeave"
  >
    <div class="flex items-start gap-3">
      <div
        class="size-9 rounded-xl grid place-items-center flex-shrink-0"
        :class="toneClasses.icon"
      >
        <span class="size-5" :class="toast.icon || 'i-lucide-list-checks'" />
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-start justify-between gap-3">
          <p class="text-sm font-semibold text-n-slate-12 truncate">
            {{ toast.title }}
          </p>
          <button
            type="button"
            :aria-label="dismissLabel"
            class="size-6 rounded-md grid place-items-center text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
            data-test-id="task-notification-toast-dismiss"
            @click.stop="$emit('dismiss')"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
        <p
          v-if="toast.body"
          class="text-[12px] text-n-slate-11 mt-1 line-clamp-2"
        >
          {{ toast.body }}
        </p>
        <div class="flex items-center gap-2 mt-3">
          <button
            type="button"
            data-test-id="task-notification-toast-view"
            class="inline-flex items-center justify-center h-7 px-3 rounded-lg bg-n-teal-9 text-n-teal-2 text-xs font-medium hover:bg-n-teal-10 transition-colors"
            @click.stop="$emit('view')"
          >
            {{ viewLabel }}
          </button>
          <button
            type="button"
            data-test-id="task-notification-toast-mark-read"
            class="inline-flex items-center justify-center h-7 px-3 rounded-lg text-xs text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
            @click.stop="$emit('markRead')"
          >
            {{ markReadLabel }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
