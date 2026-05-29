<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';

import FunnelsAPI from 'dashboard/api/funnels';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['close', 'submit']);

const { t } = useI18n();
const store = useStore();

const funnels = useMapGetter('funnels/getFunnels');
const selectedFunnelId = ref(null);
const selectedStageId = ref(null);
const stages = ref([]);
const isLoadingStages = ref(false);

const loadStages = async funnelId => {
  if (!funnelId) {
    stages.value = [];
    return;
  }
  isLoadingStages.value = true;
  try {
    const response = await FunnelsAPI.fetchStages(funnelId);
    stages.value = response.data || [];
    selectedStageId.value = stages.value[0]?.id || null;
  } finally {
    isLoadingStages.value = false;
  }
};

const onFunnelChange = id => {
  selectedFunnelId.value = id;
  loadStages(id);
};

const canSubmit = computed(
  () => Boolean(selectedFunnelId.value) && Boolean(selectedStageId.value)
);

const submit = () => {
  if (!canSubmit.value) return;
  emit('submit', {
    funnelId: selectedFunnelId.value,
    funnelStageId: selectedStageId.value,
  });
};

onMounted(async () => {
  await store.dispatch('funnels/get');
  if (funnels.value?.length) onFunnelChange(funnels.value[0].id);
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-3 backdrop-blur-sm"
    data-test-id="task-convert-modal"
    @click.self="emit('close')"
  >
    <form
      class="w-full max-w-md rounded-2xl bg-n-solid-1 ring-1 ring-n-weak shadow-2xl overflow-hidden"
      @submit.prevent="submit"
    >
      <header
        class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
      >
        <h2 class="text-[15px] font-semibold text-n-slate-12 tracking-tight">
          {{ t('TASKS.CONVERT.TITLE') }}
        </h2>
        <button
          type="button"
          class="size-7 grid place-content-center rounded-md text-n-slate-11 hover:bg-n-alpha-1"
          :aria-label="t('TASKS.DETAIL.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>

      <div class="p-5 flex flex-col gap-4">
        <label class="flex flex-col gap-1.5">
          <span
            class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
          >
            {{ t('TASKS.CONVERT.FUNNEL_LABEL') }}
          </span>
          <select
            :value="selectedFunnelId"
            class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12"
            data-test-id="task-convert-funnel"
            @change="onFunnelChange(Number($event.target.value))"
          >
            <option v-for="f in funnels" :key="f.id" :value="f.id">
              {{ f.name }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1.5">
          <span
            class="text-[12px] uppercase tracking-wide text-n-slate-10 font-medium"
          >
            {{ t('TASKS.CONVERT.STAGE_LABEL') }}
          </span>
          <select
            v-model="selectedStageId"
            :disabled="isLoadingStages"
            class="px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-inset ring-n-weak focus:ring-n-slate-7 outline-none text-sm text-n-slate-12 disabled:opacity-50"
            data-test-id="task-convert-stage"
          >
            <option v-for="s in stages" :key="s.id" :value="s.id">
              {{ s.name }}
            </option>
          </select>
        </label>
      </div>

      <footer
        class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak bg-n-alpha-1/40"
      >
        <Button
          type="button"
          :label="t('TASKS.CONVERT.CANCEL')"
          size="sm"
          ghost
          slate
          @click="emit('close')"
        />
        <Button
          type="submit"
          :label="t('TASKS.CONVERT.SUBMIT')"
          size="sm"
          solid
          blue
          :disabled="!canSubmit"
          data-test-id="task-convert-submit"
        />
      </footer>
    </form>
  </div>
</template>
