<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'next/button/Button.vue';
import SingleSelect from './inputs/SingleSelect.vue';
import MultiSelect from './inputs/MultiSelect.vue';
import {
  LIST_FILTER_PERIODS,
  NO_ASSIGNEE,
  buildListFilterConditions,
} from 'dashboard/helper/conversationListFilter';

// The filter of the conversation list: four fields over the Chatwoot filter
// engine. It edits a draft and hands it to the list on Aplicar.
const props = defineProps({
  filter: { type: Object, required: true },
});

const emit = defineEmits(['apply']);

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');
const funnels = useMapGetter('funnels/getFunnels');

const isOpen = ref(false);
const draft = ref(null);

const isActive = computed(
  () => buildListFilterConditions(props.filter).length > 0
);

const open = () => {
  draft.value = JSON.parse(JSON.stringify(props.filter));
  isOpen.value = true;
  if (!funnels.value.length) store.dispatch('funnels/get');
};

const close = () => {
  isOpen.value = false;
};

const toggle = () => (isOpen.value ? close() : open());

const periodOptions = computed(() =>
  Object.values(LIST_FILTER_PERIODS).map(period => ({
    id: period,
    name: t(`FILTER.LIST_FILTER.PERIODS.${period}`),
  }))
);

const selectPeriod = period => {
  draft.value.period = draft.value.period === period ? '' : period;
};

const assigneeOptions = computed(() => [
  { id: NO_ASSIGNEE, name: t('FILTER.LIST_FILTER.NO_ASSIGNEE') },
  ...agents.value.map(({ id, name }) => ({ id, name })),
]);

const labelOptions = computed(() =>
  labels.value.map(({ title }) => ({ id: title, name: title }))
);

const funnelOptions = computed(() =>
  funnels.value.map(({ id, name }) => ({ id, name }))
);

const selectedFunnel = computed(() =>
  funnels.value.find(funnel => funnel.id === draft.value?.funnel?.id)
);

const stageOptions = computed(() =>
  (selectedFunnel.value?.stages || []).map(({ id, name }) => ({ id, name }))
);

// The selects hold `{ id, name }` or nothing; the draft holds null for nothing.
const assigneeModel = computed({
  get: () => draft.value.assignee || {},
  set: option => {
    draft.value.assignee = option || null;
  },
});

const funnelModel = computed({
  get: () => draft.value.funnel || {},
  set: option => {
    const funnel = funnels.value.find(({ id }) => id === option?.id);
    draft.value.funnel = funnel
      ? {
          id: funnel.id,
          name: funnel.name,
          stageIds: (funnel.stages || []).map(stage => stage.id),
        }
      : null;
    draft.value.stage = null;
  },
});

const stageModel = computed({
  get: () => draft.value.stage || {},
  set: option => {
    draft.value.stage = option || null;
  },
});

const clearDraft = () => {
  draft.value = {
    ...draft.value,
    period: '',
    from: '',
    to: '',
    assignee: null,
    labels: [],
    funnel: null,
    stage: null,
  };
};

const apply = () => {
  emit('apply', draft.value);
  close();
};
</script>

<template>
  <div v-on-click-outside="close" class="relative flex-shrink-0">
    <Button
      v-tooltip.top-end="t('FILTER.TOOLTIP_LABEL')"
      icon="i-lucide-list-filter"
      xs
      faded
      :teal="isActive"
      :slate="!isActive"
      @click="toggle"
    />
    <div
      v-if="isOpen"
      class="absolute z-50 grid gap-4 p-4 mt-1 border shadow-lg top-full ltr:right-0 rtl:left-0 w-80 border-n-weak bg-n-alpha-3 backdrop-blur-[100px] rounded-xl"
    >
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('FILTER.TITLE') }}
      </h3>

      <section class="grid gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('FILTER.LIST_FILTER.PERIOD') }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="period in periodOptions"
            :key="period.id"
            type="button"
            class="px-2.5 py-1 text-xs rounded-lg outline outline-1 transition-colors"
            :class="
              draft.period === period.id
                ? 'bg-n-teal-3 text-n-teal-11 outline-n-teal-6'
                : 'bg-n-alpha-1 text-n-slate-11 outline-transparent hover:text-n-slate-12'
            "
            @click="selectPeriod(period.id)"
          >
            {{ period.name }}
          </button>
        </div>
        <div
          v-if="draft.period === LIST_FILTER_PERIODS.CUSTOM"
          class="grid grid-cols-2 gap-2"
        >
          <label class="grid gap-1 text-xs text-n-slate-11">
            {{ t('FILTER.LIST_FILTER.FROM') }}
            <input
              v-model="draft.from"
              type="date"
              :max="draft.to || undefined"
              class="h-8 px-2 mb-0 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12"
            />
          </label>
          <label class="grid gap-1 text-xs text-n-slate-11">
            {{ t('FILTER.LIST_FILTER.TO') }}
            <input
              v-model="draft.to"
              type="date"
              :min="draft.from || undefined"
              class="h-8 px-2 mb-0 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12"
            />
          </label>
        </div>
      </section>

      <section class="grid gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('FILTER.LIST_FILTER.ASSIGNEE') }}
        </span>
        <SingleSelect
          v-model="assigneeModel"
          :options="assigneeOptions"
          :placeholder="t('FILTER.LIST_FILTER.ANY_ASSIGNEE')"
          placeholder-icon="i-lucide-user"
        />
      </section>

      <section class="grid gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('FILTER.LIST_FILTER.LABELS') }}
        </span>
        <MultiSelect
          v-model="draft.labels"
          :options="labelOptions"
          :max-chips="2"
        />
      </section>

      <section class="grid gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('FILTER.LIST_FILTER.KANBAN') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <SingleSelect
            v-model="funnelModel"
            :options="funnelOptions"
            :placeholder="t('FILTER.LIST_FILTER.FUNNEL')"
            placeholder-icon="i-lucide-kanban"
            disable-search
          />
          <SingleSelect
            v-if="draft.funnel"
            v-model="stageModel"
            :options="stageOptions"
            :placeholder="t('FILTER.LIST_FILTER.ALL_STAGES')"
            placeholder-icon="i-lucide-columns-3"
            disable-search
          />
        </div>
      </section>

      <div class="flex justify-end gap-2 pt-1">
        <Button sm faded slate @click="clearDraft">
          {{ t('FILTER.LIST_FILTER.CLEAR') }}
        </Button>
        <Button sm solid blue @click="apply">
          {{ t('FILTER.SUBMIT_BUTTON_LABEL') }}
        </Button>
      </div>
    </div>
  </div>
</template>
