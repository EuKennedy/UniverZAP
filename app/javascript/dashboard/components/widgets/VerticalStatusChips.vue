<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useEmitter } from 'dashboard/composables/emitter';
import VerticalStatusesAPI from 'dashboard/api/verticalStatuses';

// UniverZAP: layer 2 of the conversation list — the active vertical's own
// pipeline stages, in order, each with how many OPEN conversations sit there.
// One scrollable line, so the list below keeps its room; a chip is just a
// link to the label's own view, which already does everything else.
const route = useRoute();
const statuses = ref([]);

const REFRESH_MS = 30_000;
let fetchedAt = 0;
async function fetchStatuses(force = false) {
  if (!force && Date.now() - fetchedAt < REFRESH_MS) return;
  fetchedAt = Date.now();
  try {
    const { data } = await VerticalStatusesAPI.get();
    statuses.value = data.statuses;
  } catch (error) {
    // No vertical configured for this account, or the request failed: the
    // row simply stays empty, the universal cards above are unaffected.
  }
}

const isActive = status =>
  route.name === 'label_conversations' && route.params.label === status.title;

onMounted(() => fetchStatuses(true));
// Same signal that refreshes the counters above, so the stages stay live.
useEmitter('fetch_conversation_stats', () => fetchStatuses());
</script>

<template>
  <ul
    v-if="statuses.length"
    class="flex items-center gap-1.5 px-3 pt-1.5 pb-2 mb-0 list-none border-b border-n-weak overflow-x-auto [scrollbar-width:none]"
  >
    <li v-for="status in statuses" :key="status.title" class="shrink-0">
      <router-link
        v-slot="{ href, navigate }"
        :to="{ name: 'label_conversations', params: { label: status.title } }"
        custom
      >
        <a
          :href="href"
          :title="status.description"
          class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full whitespace-nowrap"
          :class="
            isActive(status)
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="navigate"
        >
          <span
            class="rounded-full size-1.5"
            :style="{ backgroundColor: status.color }"
          />
          {{ status.title }}
          <span
            class="tabular-nums"
            :class="
              status.count ? 'text-n-slate-12 font-medium' : 'text-n-slate-9'
            "
          >
            {{ status.count }}
          </span>
        </a>
      </router-link>
    </li>
  </ul>
</template>
