<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const chatflows = useMapGetter('chatflows/getChatflows');
const uiFlags = useMapGetter('chatflows/getUIFlags');

const isCreating = ref(false);
const newName = ref('');

const sortedFlows = computed(() =>
  [...chatflows.value].sort((a, b) => b.id - a.id)
);

const statusTone = status =>
  ({
    active: 'text-n-teal-11 bg-n-teal-3',
    draft: 'text-n-amber-11 bg-n-amber-3',
    archived: 'text-n-slate-11 bg-n-alpha-2',
  })[status] || 'text-n-slate-11 bg-n-alpha-2';

onMounted(() => {
  store.dispatch('chatflows/get');
});

const openBuilder = flow => {
  router.push(accountScopedRoute('chatflow_builder', { chatflowId: flow.id }));
};

const startCreate = () => {
  isCreating.value = true;
  newName.value = '';
};

const cancelCreate = () => {
  isCreating.value = false;
  newName.value = '';
};

const submitCreate = async () => {
  const name = newName.value.trim();
  if (!name) return;
  try {
    const created = await store.dispatch('chatflows/create', name);
    cancelCreate();
    openBuilder(created);
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.LIST.CREATE_ERROR'));
  }
};

const removeFlow = async (flow, event) => {
  event.stopPropagation();
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CHATFLOW.LIST.DELETE_CONFIRM', { name: flow.name })))
    return;
  try {
    await store.dispatch('chatflows/delete', flow.id);
    useAlert(t('CHATFLOW.LIST.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.LIST.DELETE_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-6 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12 m-0">
          {{ t('CHATFLOW.LIST.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 m-0 max-w-2xl">
          {{ t('CHATFLOW.LIST.SUBTITLE') }}
        </p>
      </div>
      <Button
        icon="i-lucide-plus"
        :label="t('CHATFLOW.LIST.NEW')"
        @click="startCreate"
      />
    </header>

    <div class="flex-1 px-8 py-6">
      <form
        v-if="isCreating"
        class="flex items-center gap-2 mb-6 max-w-xl"
        @submit.prevent="submitCreate"
      >
        <input
          v-model="newName"
          v-focus
          type="text"
          :placeholder="t('CHATFLOW.LIST.NAME_PLACEHOLDER')"
          class="flex-1 h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
        />
        <Button
          type="submit"
          :label="t('CHATFLOW.LIST.CREATE')"
          :is-loading="uiFlags.isCreating"
        />
        <Button
          variant="ghost"
          color="slate"
          :label="t('CHATFLOW.LIST.CANCEL')"
          @click="cancelCreate"
        />
      </form>

      <div
        v-if="!sortedFlows.length && !uiFlags.isFetching"
        class="flex flex-col items-center justify-center gap-3 py-24 text-center"
      >
        <span
          class="flex items-center justify-center size-14 rounded-2xl bg-n-teal-3 text-n-teal-11"
        >
          <fluent-icon icon="bot" size="28" />
        </span>
        <h3 class="text-base font-medium text-n-slate-12 m-0">
          {{ t('CHATFLOW.LIST.EMPTY_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 m-0 max-w-md">
          {{ t('CHATFLOW.LIST.EMPTY_BODY') }}
        </p>
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <button
          v-for="flow in sortedFlows"
          :key="flow.id"
          type="button"
          class="group flex flex-col gap-3 p-5 text-left rounded-2xl bg-n-solid-1 border border-n-weak hover:border-n-teal-7 hover:shadow-lg transition-all cursor-pointer"
          @click="openBuilder(flow)"
        >
          <div class="flex items-start justify-between gap-2">
            <span
              class="flex items-center justify-center size-10 rounded-xl bg-n-teal-3 text-n-teal-11 shrink-0"
            >
              <fluent-icon icon="flow" size="20" />
            </span>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] font-medium capitalize"
              :class="statusTone(flow.status)"
            >
              {{ t(`CHATFLOW.STATUS.${flow.status.toUpperCase()}`) }}
            </span>
          </div>
          <div class="flex flex-col gap-1 min-w-0">
            <h3 class="text-sm font-semibold text-n-slate-12 m-0 truncate">
              {{ flow.name }}
            </h3>
            <p class="text-xs text-n-slate-11 m-0">
              {{ t('CHATFLOW.LIST.NODE_COUNT', { count: flow.nodes_count }) }}
            </p>
          </div>
          <div class="flex items-center justify-end mt-1">
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="removeFlow(flow, $event)"
            />
          </div>
        </button>
      </div>
    </div>
  </div>
</template>
