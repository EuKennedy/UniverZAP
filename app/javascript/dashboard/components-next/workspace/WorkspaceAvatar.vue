<script setup>
import { computed, ref, watch } from 'vue';
import {
  coverClassFor,
  workspaceInitials,
} from 'dashboard/helper/workspaceCover';

// The logo of a workspace, or its initials on the cover colors.
const props = defineProps({
  account: { type: Object, required: true },
  size: {
    type: String,
    default: 'md',
    validator: value => ['xs', 'sm', 'md', 'lg'].includes(value),
  },
});

const SIZES = {
  xs: 'size-5 rounded-md text-[0.5625rem]',
  sm: 'size-8 rounded-lg text-xs',
  md: 'size-11 rounded-xl text-sm',
  lg: 'size-16 rounded-2xl text-xl',
};

const sizeClass = computed(() => SIZES[props.size]);
const failed = ref(false);
const logoUrl = computed(() => !failed.value && props.account.logo_url);
watch(
  () => props.account.logo_url,
  () => {
    failed.value = false;
  }
);
const initials = computed(() => workspaceInitials(props.account.name));
</script>

<template>
  <span
    class="relative grid flex-shrink-0 overflow-hidden place-content-center font-semibold text-white"
    :class="[sizeClass, logoUrl ? 'bg-n-solid-1' : coverClassFor(account)]"
  >
    <img
      v-if="logoUrl"
      :src="logoUrl"
      :alt="account.name"
      class="object-cover size-full"
      @error="failed = true"
    />
    <span v-else aria-hidden="true" class="drop-shadow-sm">{{ initials }}</span>
  </span>
</template>
