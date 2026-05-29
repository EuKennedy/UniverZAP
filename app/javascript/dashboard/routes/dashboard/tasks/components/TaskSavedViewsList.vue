<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  views: {
    type: Array,
    default: () => [],
  },
  activeViewId: {
    type: [Number, String, null],
    default: null,
  },
});

const emit = defineEmits([
  'select',
  'create',
  'delete',
  'setDefault',
  'rename',
]);

const { t } = useI18n();

const isCreating = ref(false);
const newName = ref('');
const editingId = ref(null);
const editingName = ref('');

const orderedViews = computed(() =>
  [...props.views].sort((a, b) => {
    if (a.is_default && !b.is_default) return -1;
    if (!a.is_default && b.is_default) return 1;
    return (a.position || 0) - (b.position || 0);
  })
);

const startCreate = () => {
  isCreating.value = true;
  newName.value = '';
};

const cancelCreate = () => {
  isCreating.value = false;
  newName.value = '';
};

const submitCreate = () => {
  const name = newName.value.trim();
  if (!name) return;
  emit('create', name);
  cancelCreate();
};

const startEdit = view => {
  editingId.value = view.id;
  editingName.value = view.name;
};

const submitEdit = () => {
  const name = editingName.value.trim();
  if (!name || editingId.value === null) {
    editingId.value = null;
    return;
  }
  emit('rename', { id: editingId.value, name });
  editingId.value = null;
};
</script>

<template>
  <section data-test-id="task-saved-views" class="flex flex-col gap-1">
    <header
      class="flex items-center justify-between px-4 pb-2 mt-4"
      data-test-id="task-saved-views-header"
    >
      <span
        class="text-[10px] uppercase tracking-[0.12em] font-medium text-n-slate-10"
      >
        {{ t('TASKS.SAVED_VIEWS.TITLE') }}
      </span>
      <button
        type="button"
        class="size-5 grid place-content-center rounded-md text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
        :aria-label="t('TASKS.SAVED_VIEWS.NEW')"
        data-test-id="task-saved-views-create-toggle"
        @click="startCreate"
      >
        <span class="i-lucide-plus size-3.5" />
      </button>
    </header>

    <form
      v-if="isCreating"
      class="px-3 pb-2 flex items-center gap-1.5"
      data-test-id="task-saved-views-create-form"
      @submit.prevent="submitCreate"
    >
      <input
        v-model="newName"
        type="text"
        :placeholder="t('TASKS.SAVED_VIEWS.NAME_PLACEHOLDER')"
        class="flex-1 px-2.5 h-8 rounded-md text-[12px] bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-n-slate-12 placeholder:text-n-slate-10"
      />
      <button
        type="submit"
        class="size-7 grid place-content-center rounded-md bg-n-blue-9 text-white hover:bg-n-blue-10"
        :aria-label="t('TASKS.SAVED_VIEWS.SAVE')"
      >
        <span class="i-lucide-check size-3.5" />
      </button>
      <button
        type="button"
        class="size-7 grid place-content-center rounded-md text-n-slate-10 hover:bg-n-alpha-1"
        :aria-label="t('TASKS.SAVED_VIEWS.CANCEL')"
        @click="cancelCreate"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </form>

    <nav class="flex flex-col gap-0.5 px-2">
      <div
        v-for="view in orderedViews"
        :key="view.id"
        class="group flex items-center gap-2 pr-1.5 rounded-md transition-colors"
        :class="[
          Number(activeViewId) === Number(view.id)
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1',
        ]"
      >
        <template v-if="editingId === view.id">
          <input
            v-model="editingName"
            type="text"
            class="flex-1 mx-2 my-1 px-2 h-7 rounded-md text-[12px] bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-n-slate-12"
            @blur="submitEdit"
            @keydown.enter.prevent="submitEdit"
          />
        </template>
        <template v-else>
          <button
            type="button"
            class="flex-1 flex items-center gap-2 px-3 h-9 text-sm text-left"
            :data-test-id="`task-saved-view-${view.id}`"
            @click="emit('select', view)"
          >
            <span
              class="size-3.5 flex-shrink-0"
              :class="[
                view.shared
                  ? 'i-lucide-users text-n-blue-11'
                  : 'i-lucide-bookmark text-n-slate-10',
              ]"
            />
            <span class="flex-1 truncate">{{ view.name }}</span>
            <span
              v-if="view.is_default"
              v-tooltip.top="t('TASKS.SAVED_VIEWS.DEFAULT_BADGE')"
              class="size-3 i-lucide-star text-n-amber-11 flex-shrink-0"
            />
          </button>
          <div
            class="hidden group-hover:flex items-center gap-0.5 flex-shrink-0"
          >
            <button
              type="button"
              class="size-6 grid place-content-center rounded-md text-n-slate-10 hover:bg-n-alpha-2"
              :aria-label="t('TASKS.SAVED_VIEWS.SET_DEFAULT')"
              :data-test-id="`task-saved-view-default-${view.id}`"
              @click="emit('setDefault', view)"
            >
              <span class="i-lucide-star size-3" />
            </button>
            <button
              type="button"
              class="size-6 grid place-content-center rounded-md text-n-slate-10 hover:bg-n-alpha-2"
              :aria-label="t('TASKS.SAVED_VIEWS.RENAME')"
              :data-test-id="`task-saved-view-rename-${view.id}`"
              @click="startEdit(view)"
            >
              <span class="i-lucide-pencil size-3" />
            </button>
            <button
              type="button"
              class="size-6 grid place-content-center rounded-md text-n-slate-10 hover:bg-n-ruby-3 hover:text-n-ruby-11"
              :aria-label="t('TASKS.SAVED_VIEWS.DELETE')"
              :data-test-id="`task-saved-view-delete-${view.id}`"
              @click="emit('delete', view)"
            >
              <span class="i-lucide-trash-2 size-3" />
            </button>
          </div>
        </template>
      </div>
      <p
        v-if="!orderedViews.length && !isCreating"
        class="px-4 py-2 text-[12px] text-n-slate-10 leading-tight"
      >
        {{ t('TASKS.SAVED_VIEWS.EMPTY') }}
      </p>
    </nav>
  </section>
</template>
