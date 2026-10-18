<script setup>
import { ref, onMounted } from 'vue';
import VerticalStatusesAPI from 'dashboard/api/verticalStatuses';

// UniverZAP: layer 2 of the conversation list's quick filters — the active
// vertical's own pipeline statuses (labels), read-only counts. Each chip is
// just a link to the label's own conversation view, which already exists and
// already supports everything (pagination, realtime, filters).
const statuses = ref([]);

onMounted(async () => {
  try {
    const { data } = await VerticalStatusesAPI.get();
    statuses.value = data.statuses;
  } catch (error) {
    // No vertical configured for this account, or the request failed: the
    // row simply stays empty, the universal pills above are unaffected.
  }
});
</script>

<template>
  <ul
    v-if="statuses.length"
    class="flex items-center flex-wrap gap-1.5 px-3 pt-1.5 pb-2 mb-0 list-none border-b border-n-weak"
  >
    <li v-for="status in statuses" :key="status.title">
      <router-link
        v-slot="{ href, navigate }"
        :to="{ name: 'label_conversations', params: { label: status.title } }"
        custom
      >
        <a
          :href="href"
          class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2"
          @click="navigate"
        >
          <span
            class="rounded-full size-1.5"
            :style="{ backgroundColor: status.color }"
          />
          {{ status.title }}
          <span class="text-n-slate-10">{{ status.count }}</span>
        </a>
      </router-link>
    </li>
  </ul>
</template>
