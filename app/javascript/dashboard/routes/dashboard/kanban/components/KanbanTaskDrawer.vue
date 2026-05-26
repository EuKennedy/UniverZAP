<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';

const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'update:show']);

const panelRef = ref(null);
let lastFocusedBeforeOpen = null;

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'textarea:not([disabled])',
  'select:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

const focusableElements = () => {
  if (!panelRef.value) return [];
  return Array.from(panelRef.value.querySelectorAll(FOCUSABLE_SELECTOR)).filter(
    el => !el.hasAttribute('aria-hidden') && el.offsetParent !== null
  );
};

const closeDrawer = () => {
  emit('update:show', false);
  emit('close');
};

// LGPD/A11y: trap Tab inside the drawer while open. Returning focus to the
// trigger after close keeps screen-reader users anchored.
const handleKeydown = event => {
  if (!props.show) return;
  if (event.key === 'Escape') {
    closeDrawer();
    return;
  }
  if (event.key !== 'Tab') return;

  const items = focusableElements();
  if (!items.length) return;
  const first = items[0];
  const last = items[items.length - 1];
  const active = document.activeElement;

  if (event.shiftKey && active === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  }
};

const handleBackdrop = event => {
  if (event.target === event.currentTarget) closeDrawer();
};

// Lock background scroll while the drawer is mounted so the desktop board
// doesn't shift behind the panel. On open we also remember the previously
// focused element + push focus into the panel for a11y.
watch(
  () => props.show,
  visible => {
    if (visible) {
      lastFocusedBeforeOpen = document.activeElement;
      document.body.classList.add('kanban-drawer-open');
      nextTick(() => focusableElements()[0]?.focus());
    } else {
      document.body.classList.remove('kanban-drawer-open');
      lastFocusedBeforeOpen?.focus?.();
      lastFocusedBeforeOpen = null;
    }
  }
);

onMounted(() => {
  document.addEventListener('keydown', handleKeydown);
});
onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleKeydown);
  document.body.classList.remove('kanban-drawer-open');
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-200 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        class="fixed inset-0 z-[60] bg-n-slate-12/70 backdrop-blur-sm"
        @mousedown="handleBackdrop"
      >
        <Transition
          enter-active-class="transition-transform duration-300 ease-out"
          enter-from-class="translate-x-full"
          enter-to-class="translate-x-0"
          leave-active-class="transition-transform duration-200 ease-in"
          leave-from-class="translate-x-0"
          leave-to-class="translate-x-full"
          appear
        >
          <aside
            v-if="show"
            ref="panelRef"
            class="absolute right-0 top-0 bottom-0 w-full sm:w-[720px] md:w-[820px] xl:w-[920px] bg-n-surface-1 shadow-2xl flex flex-col"
            role="dialog"
            aria-modal="true"
            @mousedown.stop
          >
            <slot :close="closeDrawer" />
          </aside>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<style>
body.kanban-drawer-open {
  overflow: hidden;
}
</style>
