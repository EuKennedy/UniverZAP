<script setup>
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';

const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'update:show']);

const panelRef = ref(null);

const closeDrawer = () => {
  emit('update:show', false);
  emit('close');
};

const handleEsc = event => {
  if (event.key === 'Escape' && props.show) closeDrawer();
};

const handleBackdrop = event => {
  if (event.target === event.currentTarget) closeDrawer();
};

// Lock background scroll while the drawer is mounted so the desktop board
// doesn't shift behind the panel.
watch(
  () => props.show,
  visible => {
    if (visible) document.body.classList.add('kanban-drawer-open');
    else document.body.classList.remove('kanban-drawer-open');
  }
);

onMounted(() => {
  document.addEventListener('keydown', handleEsc);
});
onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleEsc);
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
