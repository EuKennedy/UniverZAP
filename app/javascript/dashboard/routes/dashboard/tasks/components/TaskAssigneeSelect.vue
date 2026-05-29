<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { vOnClickOutside } from '@vueuse/components';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();

const agents = useMapGetter('agents/getAgents');

onMounted(() => {
  if (!agents.value?.length) {
    store.dispatch('agents/get');
  }
});

const isOpen = ref(false);
const query = ref('');

const close = () => {
  isOpen.value = false;
  query.value = '';
};

const selected = computed(() =>
  (agents.value || []).filter(agent =>
    props.modelValue.some(id => Number(id) === Number(agent.id))
  )
);

const filteredAgents = computed(() => {
  const term = query.value.trim().toLowerCase();
  const list = agents.value || [];
  if (!term) return list;
  return list.filter(
    agent =>
      agent.name?.toLowerCase().includes(term) ||
      agent.email?.toLowerCase().includes(term)
  );
});

const isSelected = id =>
  props.modelValue.some(value => Number(value) === Number(id));

const toggleAgent = agent => {
  if (isSelected(agent.id)) {
    emit(
      'update:modelValue',
      props.modelValue.filter(id => Number(id) !== Number(agent.id))
    );
  } else {
    emit('update:modelValue', [...props.modelValue, agent.id]);
  }
};

const removeAgent = id => {
  emit(
    'update:modelValue',
    props.modelValue.filter(value => Number(value) !== Number(id))
  );
};
</script>

<template>
  <div v-on-click-outside="close" class="relative">
    <button
      type="button"
      class="flex flex-wrap items-center gap-1.5 min-h-9 w-full px-2 py-1.5 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak hover:ring-n-slate-7 focus-within:ring-n-slate-7 transition text-left"
      @click="isOpen = !isOpen"
    >
      <template v-if="selected.length">
        <span
          v-for="agent in selected"
          :key="agent.id"
          class="inline-flex items-center gap-1.5 pl-1 pr-1.5 h-6 rounded-full bg-n-solid-1 ring-1 ring-n-weak text-[12px] text-n-slate-12"
          @click.stop
        >
          <Avatar :name="agent.name" :src="agent.thumbnail" :size="18" />
          <span class="max-w-[160px] truncate">{{ agent.name }}</span>
          <button
            type="button"
            class="size-3 text-n-slate-10 hover:text-n-slate-12"
            :aria-label="t('TASKS.ROW.ASSIGN')"
            @click.stop="removeAgent(agent.id)"
          >
            <span class="i-lucide-x size-3" />
          </button>
        </span>
      </template>
      <span v-else class="text-sm text-n-slate-10 px-1">
        {{ t('TASKS.CREATE.ASSIGNEES_PLACEHOLDER') }}
      </span>
      <span class="i-lucide-chevron-down ml-auto text-n-slate-10 size-4" />
    </button>

    <div
      v-if="isOpen"
      class="absolute left-0 right-0 z-30 mt-1.5 max-h-72 overflow-y-auto rounded-xl bg-n-solid-1 ring-1 ring-n-weak shadow-xl"
    >
      <div class="p-2">
        <div
          class="flex items-center gap-2 px-2.5 py-1.5 rounded-md bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
        >
          <span class="i-lucide-search size-3.5 text-n-slate-10" />
          <input
            v-model="query"
            type="text"
            :placeholder="t('TASKS.CREATE.ASSIGNEES_PLACEHOLDER')"
            class="flex-1 bg-transparent outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
          />
        </div>
      </div>
      <ul class="px-1 pb-2 list-none m-0">
        <li v-for="agent in filteredAgents" :key="agent.id">
          <button
            type="button"
            class="flex w-full items-center gap-3 px-2 py-1.5 rounded-md hover:bg-n-alpha-1 text-left"
            @click="toggleAgent(agent)"
          >
            <Avatar :name="agent.name" :src="agent.thumbnail" :size="24" />
            <span class="flex-1 min-w-0">
              <span class="block text-sm text-n-slate-12 truncate">
                {{ agent.name }}
              </span>
              <span class="block text-[11px] text-n-slate-10 truncate">
                {{ agent.email }}
              </span>
            </span>
            <span
              v-if="isSelected(agent.id)"
              class="i-lucide-check size-4 text-n-teal-11"
            />
          </button>
        </li>
        <li
          v-if="!filteredAgents.length"
          class="px-3 py-3 text-center text-sm text-n-slate-10"
        >
          {{ t('TASKS.FILTERS.ANY') }}
        </li>
      </ul>
    </div>
  </div>
</template>
