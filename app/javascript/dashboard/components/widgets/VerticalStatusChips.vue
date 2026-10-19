<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useEmitter } from 'dashboard/composables/emitter';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import VerticalStatusesAPI from 'dashboard/api/verticalStatuses';

// UniverZAP: layer 2 of the conversation list — the labels the account wants
// as its pipeline, in order, each with how many OPEN conversations sit there.
// One scrollable line, so the list below keeps its room; a chip is just a
// link to the label's own view, which already does everything else. An admin
// picks which labels appear (for the whole team); unset, the vertical's own
// pipeline statuses show.
const route = useRoute();
const { isAdmin } = useAdmin();
const accountLabels = useMapGetter('labels/getLabels');

const statuses = ref([]);
const picking = ref(false);
const picked = ref([]);
const saving = ref(false);

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

function openPicker() {
  picked.value = statuses.value.map(status => status.title);
  picking.value = true;
}

// The order you tick is the order on the bar.
function toggle(title) {
  picked.value = picked.value.includes(title)
    ? picked.value.filter(item => item !== title)
    : [...picked.value, title];
}

async function save(titles) {
  saving.value = true;
  try {
    await VerticalStatusesAPI.updateSelection(titles);
    picking.value = false;
    await fetchStatuses(true);
  } finally {
    saving.value = false;
  }
}

onMounted(() => fetchStatuses(true));
// Same signal that refreshes the counters above, so the stages stay live.
useEmitter('fetch_conversation_stats', () => fetchStatuses());
</script>

<template>
  <div
    v-if="statuses.length || isAdmin"
    class="relative border-b border-n-weak"
  >
    <ul
      class="flex items-center gap-1.5 px-3 pt-1.5 pb-2 mb-0 list-none overflow-x-auto [scrollbar-width:none]"
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
      <li v-if="isAdmin" class="shrink-0 ml-auto">
        <button
          type="button"
          class="flex items-center justify-center rounded-full size-6 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="$t('CHAT_LIST.STATUS_BAR.PICK')"
          @click="picking ? (picking = false) : openPicker()"
        >
          <span class="i-lucide-settings-2 size-3.5" />
        </button>
      </li>
    </ul>

    <div
      v-if="picking"
      class="absolute right-2 top-full z-30 w-72 p-3 mt-1 rounded-xl border border-n-weak bg-n-solid-2 shadow-lg"
    >
      <p class="mb-2 text-xs font-medium text-n-slate-12">
        {{ $t('CHAT_LIST.STATUS_BAR.PICK') }}
      </p>
      <p class="mb-2 text-xs text-n-slate-11">
        {{ $t('CHAT_LIST.STATUS_BAR.HINT') }}
      </p>
      <ul class="mb-3 overflow-y-auto list-none max-h-56">
        <li v-for="label in accountLabels" :key="label.id">
          <label
            class="flex items-center gap-2 px-1 py-1 text-xs rounded cursor-pointer text-n-slate-12 hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              class="!m-0"
              :checked="picked.includes(label.title)"
              @change="toggle(label.title)"
            />
            <span
              class="rounded-full size-1.5"
              :style="{ backgroundColor: label.color }"
            />
            <span class="truncate">{{ label.title }}</span>
            <span
              v-if="picked.includes(label.title)"
              class="ml-auto text-n-slate-10 tabular-nums"
            >
              {{ picked.indexOf(label.title) + 1 }}
            </span>
          </label>
        </li>
      </ul>
      <div class="flex items-center justify-between gap-2">
        <button
          type="button"
          class="text-xs text-n-slate-11 hover:text-n-slate-12"
          :disabled="saving"
          @click="save([])"
        >
          {{ $t('CHAT_LIST.STATUS_BAR.RESET') }}
        </button>
        <button
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-md bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-60"
          :disabled="saving"
          @click="save(picked)"
        >
          {{ $t('CHAT_LIST.STATUS_BAR.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
