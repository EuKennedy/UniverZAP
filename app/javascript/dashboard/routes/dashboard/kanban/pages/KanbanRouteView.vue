<script setup>
import { onMounted } from 'vue';
import { useStore } from 'vuex';

const store = useStore();

onMounted(() => {
  store.dispatch('funnels/get');
  store.dispatch('agents/get');
  store.dispatch('inboxes/get');
  store.dispatch('labels/get');
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <router-view />
  </div>
</template>
