<script setup>
import { computed, ref, watch } from 'vue';
import { coverClassFor } from 'dashboard/helper/workspaceCover';

// The cover band of a workspace: the uploaded image when there is one,
// otherwise the chosen theme, otherwise a gradient derived from the name.
const props = defineProps({
  account: { type: Object, required: true },
});

// A broken image (e.g. no image processor) falls back to the colors.
const failed = ref(false);
const coverUrl = computed(() => !failed.value && props.account.cover_url);
watch(
  () => props.account.cover_url,
  () => {
    failed.value = false;
  }
);
const themeClass = computed(() => coverClassFor(props.account));
</script>

<template>
  <div class="relative overflow-hidden" :class="themeClass">
    <img
      v-if="coverUrl"
      :src="coverUrl"
      alt=""
      class="absolute inset-0 object-cover size-full"
      @error="failed = true"
    />
    <template v-else>
      <div
        class="absolute -top-1/2 -right-1/4 size-full rounded-full bg-white/15 blur-2xl"
      />
      <div
        class="absolute -bottom-3/4 -left-1/4 size-full rounded-full bg-n-black/10 blur-2xl"
      />
    </template>
    <div
      class="absolute inset-0 bg-gradient-to-b from-transparent to-n-black/20"
    />
    <slot />
  </div>
</template>
