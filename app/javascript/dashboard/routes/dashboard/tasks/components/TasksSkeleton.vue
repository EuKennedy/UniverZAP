<script setup>
defineProps({
  rows: {
    type: Number,
    default: 5,
  },
});
</script>

<template>
  <div class="flex flex-col gap-1 px-6 py-4">
    <div
      v-for="i in rows"
      :key="i"
      class="flex items-center gap-3 px-3 py-2.5 rounded-lg ring-1 ring-n-weak/40 bg-n-alpha-1 animate-pulse"
    >
      <div class="size-4 rounded bg-n-alpha-2" />
      <div
        class="h-3 rounded bg-n-alpha-2"
        :style="{ width: `${30 + ((i * 7) % 40)}%` }"
      />
      <div class="ml-auto flex items-center gap-2">
        <div class="size-6 rounded-full bg-n-alpha-2" />
        <div class="size-5 w-14 rounded-md bg-n-alpha-2" />
        <div class="size-5 w-20 rounded-md bg-n-alpha-2" />
      </div>
    </div>
  </div>
</template>
