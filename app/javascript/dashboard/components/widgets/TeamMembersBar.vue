<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import TeamContactsAPI from 'dashboard/api/teamContacts';
import ContactAPI from 'dashboard/api/contacts';

// UniverZAP: who is in the Equipe tab — the people of the business itself, so
// talking to them is one click away and never mixes with the customer queues.
// Everyone sees the team; an admin adds people by searching contacts and
// takes them out with the ×.
const emit = defineEmits(['changed']);

const { isAdmin } = useAdmin();

const members = ref([]);
const picking = ref(false);
const query = ref('');
const results = ref([]);
const busy = ref(false);

const memberIds = computed(() => new Set(members.value.map(m => m.id)));

async function load() {
  const { data } = await TeamContactsAPI.get();
  members.value = data.payload || [];
}

let searchTimer;
watch(query, value => {
  clearTimeout(searchTimer);
  if (value.trim().length < 2) {
    results.value = [];
    return;
  }
  searchTimer = setTimeout(async () => {
    const { data } = await ContactAPI.search(value.trim());
    results.value = (data.payload || [])
      .filter(c => !memberIds.value.has(c.id))
      .slice(0, 8);
  }, 250);
});

async function change(action, contactId) {
  busy.value = true;
  try {
    await TeamContactsAPI[action](contactId);
    await load();
    results.value = results.value.filter(c => c.id !== contactId);
    emit('changed');
  } finally {
    busy.value = false;
  }
}

function close() {
  picking.value = false;
  query.value = '';
  results.value = [];
}

onMounted(load);
</script>

<template>
  <div class="relative px-3 py-2 border-b border-n-weak">
    <div
      class="flex items-center gap-1.5 overflow-x-auto [scrollbar-width:none]"
    >
      <span class="i-lucide-users size-3.5 shrink-0 text-n-slate-11" />
      <span v-if="!members.length" class="text-xs text-n-slate-10 shrink-0">
        {{ $t('CHAT_LIST.TEAM.EMPTY') }}
      </span>
      <span
        v-for="member in members"
        :key="member.id"
        class="group flex items-center gap-1 px-2 py-0.5 text-xs rounded-md shrink-0 bg-brand-gradient-soft text-n-teal-11"
      >
        {{ member.name }}
        <button
          v-if="isAdmin"
          type="button"
          class="hidden group-hover:inline i-lucide-x size-3"
          :title="$t('CHAT_LIST.TEAM.REMOVE', { name: member.name })"
          :disabled="busy"
          @click="change('remove', member.id)"
        />
      </span>
      <button
        v-if="isAdmin"
        type="button"
        class="flex items-center gap-1 px-2 py-0.5 ml-auto text-xs rounded-md shrink-0 text-n-slate-11 hover:bg-n-alpha-2"
        @click="picking ? close() : (picking = true)"
      >
        <span class="i-lucide-user-plus size-3.5" />
        {{ $t('CHAT_LIST.TEAM.ADD') }}
      </button>
    </div>

    <div
      v-if="picking"
      class="absolute z-20 p-2 mt-1 border rounded-lg shadow-lg left-3 right-3 bg-n-solid-2 border-n-weak"
    >
      <input
        v-model="query"
        type="search"
        class="w-full px-2 py-1 mb-1 text-sm rounded-md bg-n-alpha-1 text-n-slate-12"
        :placeholder="$t('CHAT_LIST.TEAM.SEARCH')"
        autofocus
      />
      <p class="mb-1 text-xs text-n-slate-10">
        {{ $t('CHAT_LIST.TEAM.HINT') }}
      </p>
      <ul class="mb-0 list-none max-h-60 overflow-y-auto">
        <li v-for="contact in results" :key="contact.id">
          <button
            type="button"
            class="flex items-center justify-between w-full px-2 py-1.5 text-sm rounded-md hover:bg-n-alpha-2 text-start"
            :disabled="busy"
            @click="change('add', contact.id)"
          >
            <span class="truncate text-n-slate-12">{{ contact.name }}</span>
            <span class="text-xs text-n-slate-10 shrink-0 tabular-nums">
              {{ contact.phone_number }}
            </span>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>
