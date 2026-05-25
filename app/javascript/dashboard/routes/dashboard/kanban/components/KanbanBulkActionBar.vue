<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  count: { type: Number, required: true },
  stages: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
});

const emit = defineEmits(['move', 'assign', 'delete', 'clear']);

const { t } = useI18n();

const showMoveMenu = ref(false);
const showAssignMenu = ref(false);

const onMove = stageId => {
  showMoveMenu.value = false;
  emit('move', stageId);
};
const onAssign = agentId => {
  showAssignMenu.value = false;
  emit('assign', agentId);
};
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 translate-y-2"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 translate-y-0"
      leave-to-class="opacity-0 translate-y-2"
    >
      <aside
        v-if="props.count > 0"
        class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 inline-flex items-center gap-2 px-2 py-2 rounded-2xl bg-n-slate-12 dark:bg-n-solid-2 ring-1 ring-n-teal-9/40 shadow-[0_24px_60px_-20px_rgba(0,0,0,0.7)] backdrop-blur-xl"
        role="toolbar"
        :aria-label="t('KANBAN.BULK.LABEL')"
      >
        <span
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-n-teal-9 text-white text-[12px] font-semibold tabular-nums"
        >
          <Icon icon="i-lucide-check-square-2" class="size-3.5" />
          {{ count }}
        </span>

        <!-- Move -->
        <div class="relative">
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[12px] font-medium text-white hover:bg-white/10 transition-colors cursor-pointer"
            @click="showMoveMenu = !showMoveMenu"
          >
            <Icon icon="i-lucide-move-right" class="size-3.5" />
            {{ t('KANBAN.BULK.MOVE') }}
          </button>
          <ul
            v-if="showMoveMenu"
            class="absolute bottom-full left-0 mb-2 min-w-[200px] max-h-72 overflow-y-auto rounded-xl bg-n-solid-2 ring-1 ring-n-weak shadow-2xl py-1.5"
            @mouseleave="showMoveMenu = false"
          >
            <li v-for="stage in stages" :key="stage.id">
              <button
                type="button"
                class="w-full flex items-center gap-2 px-3 py-2 text-left text-[12.5px] text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
                @click="onMove(stage.id)"
              >
                <span
                  class="size-2.5 rounded-full flex-shrink-0"
                  :style="{ backgroundColor: stage.color }"
                />
                {{ stage.name }}
              </button>
            </li>
          </ul>
        </div>

        <!-- Assign -->
        <div class="relative">
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[12px] font-medium text-white hover:bg-white/10 transition-colors cursor-pointer"
            @click="showAssignMenu = !showAssignMenu"
          >
            <Icon icon="i-lucide-user-check" class="size-3.5" />
            {{ t('KANBAN.BULK.ASSIGN') }}
          </button>
          <ul
            v-if="showAssignMenu"
            class="absolute bottom-full left-0 mb-2 min-w-[220px] max-h-72 overflow-y-auto rounded-xl bg-n-solid-2 ring-1 ring-n-weak shadow-2xl py-1.5"
            @mouseleave="showAssignMenu = false"
          >
            <li>
              <button
                type="button"
                class="w-full flex items-center gap-2 px-3 py-2 text-left text-[12.5px] text-n-slate-11 hover:bg-n-alpha-2 transition-colors cursor-pointer"
                @click="onAssign(null)"
              >
                <Icon icon="i-lucide-user-x" class="size-3.5" />
                {{ t('KANBAN.BULK.UNASSIGN') }}
              </button>
            </li>
            <li v-for="agent in agents" :key="agent.id">
              <button
                type="button"
                class="w-full flex items-center gap-2 px-3 py-2 text-left text-[12.5px] text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
                @click="onAssign(agent.id)"
              >
                <span
                  class="size-5 rounded-full bg-n-alpha-2 inline-flex items-center justify-center text-[10px] font-semibold text-n-slate-11"
                >
                  {{ agent.name.slice(0, 1) }}
                </span>
                {{ agent.name }}
              </button>
            </li>
          </ul>
        </div>

        <!-- Delete -->
        <button
          type="button"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[12px] font-medium text-n-ruby-3 hover:bg-n-ruby-9/30 transition-colors cursor-pointer"
          @click="emit('delete')"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
          {{ t('KANBAN.BULK.DELETE') }}
        </button>

        <span class="w-px h-5 bg-white/15 mx-1" aria-hidden="true" />

        <!-- Clear -->
        <button
          type="button"
          class="inline-flex items-center justify-center size-7 rounded-xl text-white/70 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
          :aria-label="t('KANBAN.BULK.CLEAR')"
          @click="emit('clear')"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </aside>
    </Transition>
  </Teleport>
</template>
