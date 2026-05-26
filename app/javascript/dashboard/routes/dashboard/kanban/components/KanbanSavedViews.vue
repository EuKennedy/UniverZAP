<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useKanbanSavedViews } from '../composables/useKanbanSavedViews';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  funnelId: { type: [String, Number], required: true },
  currentFilters: { type: Object, required: true },
  activeFilterCount: { type: Number, default: 0 },
});

const emit = defineEmits(['apply']);

const { t } = useI18n();
const { viewsForFunnel, saveView, deleteView } = useKanbanSavedViews();

const isOpen = ref(false);
const isSaving = ref(false);
const newViewName = ref('');
const rootRef = ref(null);

const views = computed(() => viewsForFunnel(props.funnelId));

const close = () => {
  isOpen.value = false;
  newViewName.value = '';
};

const onClickOutside = event => {
  if (rootRef.value && !rootRef.value.contains(event.target)) close();
};
const onEsc = event => {
  if (event.key === 'Escape' && isOpen.value) close();
};

const toggle = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    document.addEventListener('mousedown', onClickOutside);
    document.addEventListener('keydown', onEsc);
  } else {
    document.removeEventListener('mousedown', onClickOutside);
    document.removeEventListener('keydown', onEsc);
  }
};

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onClickOutside);
  document.removeEventListener('keydown', onEsc);
});

const onSave = async () => {
  const name = newViewName.value.trim();
  if (!name || isSaving.value) return;
  isSaving.value = true;
  try {
    await saveView({
      name,
      funnelId: props.funnelId,
      filters: { ...props.currentFilters },
    });
    newViewName.value = '';
  } finally {
    isSaving.value = false;
  }
};

const onApply = view => {
  emit('apply', view.filters);
  close();
};

const onDelete = async (event, view) => {
  event.stopPropagation();
  await deleteView(view.id);
};

const canSave = computed(() => props.activeFilterCount > 0);
</script>

<template>
  <div ref="rootRef" class="relative">
    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg ring-1 ring-inset bg-n-alpha-1 ring-n-weak text-[11px] font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors cursor-pointer"
      :class="{ 'text-n-slate-12 ring-n-slate-7': isOpen }"
      :aria-expanded="isOpen"
      :aria-haspopup="true"
      @click="toggle"
    >
      <Icon icon="i-lucide-bookmark" class="size-3.5" />
      {{ t('KANBAN.VIEWS.LABEL') }}
      <span
        v-if="views.length"
        class="text-n-teal-11 tabular-nums font-semibold"
      >
        {{ views.length }}
      </span>
      <Icon icon="i-lucide-chevron-down" class="size-3" />
    </button>

    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0 -translate-y-1"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-100 ease-in"
      leave-from-class="opacity-100 translate-y-0"
      leave-to-class="opacity-0 -translate-y-1"
    >
      <div
        v-if="isOpen"
        class="absolute top-full left-0 mt-2 z-30 min-w-[280px] max-w-[360px] rounded-xl bg-n-surface-2 ring-1 ring-n-weak shadow-2xl overflow-hidden"
      >
        <header
          class="px-4 py-3 border-b border-n-weak flex items-center gap-2"
        >
          <Icon
            icon="i-lucide-bookmark"
            class="size-3.5 text-n-teal-11 flex-shrink-0"
          />
          <span class="text-xs font-semibold text-n-slate-12 truncate">
            {{ t('KANBAN.VIEWS.TITLE') }}
          </span>
        </header>

        <ul
          v-if="views.length"
          class="flex flex-col py-1 max-h-64 overflow-y-auto"
        >
          <li v-for="view in views" :key="view.id">
            <button
              type="button"
              class="group w-full flex items-center gap-2 px-4 py-2 text-left text-[13px] text-n-slate-12 hover:bg-n-alpha-1 transition-colors cursor-pointer"
              @click="onApply(view)"
            >
              <Icon
                icon="i-lucide-eye"
                class="size-3.5 text-n-slate-10 flex-shrink-0"
              />
              <span class="flex-1 truncate">{{ view.name }}</span>
              <button
                type="button"
                class="opacity-0 group-hover:opacity-100 size-6 rounded-md grid place-content-center text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2 transition-all duration-150 cursor-pointer"
                :aria-label="t('KANBAN.VIEWS.DELETE')"
                @click="onDelete($event, view)"
              >
                <span class="i-lucide-trash-2 size-3.5" />
              </button>
            </button>
          </li>
        </ul>
        <p
          v-else
          class="px-4 py-4 text-[12px] text-n-slate-11 text-center leading-relaxed"
        >
          {{ t('KANBAN.VIEWS.EMPTY') }}
        </p>

        <footer class="px-4 py-3 border-t border-n-weak bg-n-alpha-1/40">
          <p
            class="text-[10.5px] font-semibold text-n-slate-11 uppercase tracking-wider mb-2"
          >
            {{ t('KANBAN.VIEWS.SAVE_CURRENT') }}
          </p>
          <div
            class="flex items-center gap-2 px-2.5 py-1.5 rounded-md bg-n-solid-1 ring-1 ring-n-weak focus-within:ring-n-brand"
            :class="{ 'opacity-60': !canSave }"
          >
            <Icon
              icon="i-lucide-plus"
              class="size-3.5 text-n-slate-10 flex-shrink-0"
            />
            <input
              v-model="newViewName"
              type="text"
              :placeholder="t('KANBAN.VIEWS.NAME_PLACEHOLDER')"
              :disabled="!canSave || isSaving"
              class="flex-1 bg-transparent text-[12.5px] text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
              @keydown.enter.prevent="onSave"
            />
            <button
              type="button"
              class="text-[11px] font-semibold text-n-teal-11 hover:text-n-teal-12 disabled:opacity-50 transition-colors cursor-pointer"
              :disabled="!canSave || !newViewName.trim() || isSaving"
              @click="onSave"
            >
              {{ t('KANBAN.VIEWS.SAVE') }}
            </button>
          </div>
          <p
            v-if="!canSave"
            class="text-[10.5px] text-n-slate-10 mt-1.5 leading-relaxed"
          >
            {{ t('KANBAN.VIEWS.NEEDS_FILTER') }}
          </p>
        </footer>
      </div>
    </Transition>
  </div>
</template>
