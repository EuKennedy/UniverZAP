<script setup>
import { ref } from 'vue';
import { vOnClickOutside } from '@vueuse/components';

// A chip of the toolbar and the panel it opens.
defineProps({
  label: { type: String, required: true },
  icon: { type: String, default: '' },
  // What is selected, shown in the chip; empty means nothing is.
  value: { type: String, default: '' },
  align: { type: String, default: 'start' },
});

const emit = defineEmits(['clear']);

const isOpen = ref(false);
const close = () => {
  isOpen.value = false;
};
</script>

<template>
  <div v-on-click-outside="close" class="relative flex-shrink-0">
    <button
      type="button"
      class="inline-flex items-center h-8 gap-1.5 px-2.5 text-xs font-medium transition rounded-lg outline outline-1 -outline-offset-1"
      :class="
        value
          ? 'bg-brand-gradient-soft text-n-teal-11 outline-n-teal-7'
          : 'bg-n-solid-2 text-n-slate-11 outline-n-weak hover:text-n-slate-12 hover:outline-n-strong'
      "
      :aria-expanded="isOpen"
      @click="isOpen = !isOpen"
    >
      <span v-if="icon" class="size-3.5" :class="icon" />
      <span class="whitespace-nowrap">{{ label }}</span>
      <span v-if="value" class="max-w-32 truncate">: {{ value }}</span>
      <span
        v-if="value"
        role="button"
        class="i-lucide-x size-3 opacity-70 hover:opacity-100"
        @click.stop="emit('clear')"
      />
      <span v-else class="i-lucide-chevron-down size-3 opacity-60" />
    </button>
    <div
      v-if="isOpen"
      class="absolute z-30 p-1 mt-1 overflow-y-auto border rounded-xl shadow-lg top-full max-h-80 min-w-48 w-max max-w-72 bg-n-solid-2 border-n-weak"
      :class="align === 'end' ? 'end-0' : 'start-0'"
    >
      <slot :close="close" />
    </div>
  </div>
</template>
