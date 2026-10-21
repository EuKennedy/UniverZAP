<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import ChatflowsAPI from 'dashboard/api/chatflows';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { KIND_META, TONE_CLASSES } from '../helpers/nodeKinds';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const chatflows = useMapGetter('chatflows/getChatflows');
const uiFlags = useMapGetter('chatflows/getUIFlags');

const TABS = ['flows', 'templates'];
const tab = ref('flows');
const query = ref('');
const isCreating = ref(false);
const newName = ref('');
const templates = ref([]);
const installingKey = ref(null);

const sortedFlows = computed(() => {
  const term = query.value.trim().toLowerCase();
  return [...chatflows.value]
    .filter(f => !term || f.name.toLowerCase().includes(term))
    .sort((a, b) => b.id - a.id);
});

const statOf = (flow, key) => flow.stats?.[key] || 0;

// Métricas dos últimos 30 dias, somadas de todos os fluxos.
const cards = computed(() => {
  const flows = chatflows.value;
  const sum = key => flows.reduce((acc, f) => acc + statOf(f, key), 0);
  const started = sum('started');
  const completed = sum('completed');
  return [
    {
      key: 'ACTIVE',
      icon: 'i-lucide-zap',
      tone: 'bg-n-teal-3 text-n-teal-11',
      value: flows.filter(f => f.status === 'active').length,
      hint: t('CHATFLOW.LIST.STATS.ACTIVE_HINT', { total: flows.length }),
    },
    {
      key: 'STARTED',
      icon: 'i-lucide-play',
      tone: 'bg-n-blue-3 text-n-blue-11',
      value: started,
      hint: t('CHATFLOW.LIST.STATS.PERIOD'),
    },
    {
      key: 'COMPLETED',
      icon: 'i-lucide-flag',
      tone: 'bg-n-iris-3 text-n-iris-11',
      value: completed,
      hint: started
        ? t('CHATFLOW.LIST.STATS.RATE', {
            rate: Math.round((completed / started) * 100),
          })
        : t('CHATFLOW.LIST.STATS.PERIOD'),
    },
    {
      key: 'LIVE',
      icon: 'i-lucide-activity',
      tone: 'bg-n-amber-3 text-n-amber-11',
      value: sum('live'),
      hint: t('CHATFLOW.LIST.STATS.LIVE_HINT'),
    },
  ];
});

const statusTone = status =>
  ({
    active: 'text-n-teal-11 bg-n-teal-3',
    draft: 'text-n-amber-11 bg-n-amber-3',
    archived: 'text-n-slate-11 bg-n-alpha-2',
  })[status] || 'text-n-slate-11 bg-n-alpha-2';

const loadTemplates = async () => {
  try {
    const { data } = await ChatflowsAPI.templates();
    templates.value = data.templates;
  } catch {
    templates.value = [];
  }
};

onMounted(() => {
  store.dispatch('chatflows/get');
  loadTemplates();
});

const openBuilder = flow => {
  router.push(accountScopedRoute('chatflow_builder', { chatflowId: flow.id }));
};

const startCreate = () => {
  tab.value = 'flows';
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

// O modelo vira um fluxo em RASCUNHO: o dono revisa os textos e só então liga.
const useTemplate = async template => {
  installingKey.value = template.key;
  try {
    const created = await store.dispatch(
      'chatflows/fromTemplate',
      template.key
    );
    useAlert(t('CHATFLOW.TEMPLATES.INSTALLED'));
    openBuilder(created);
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.TEMPLATES.ERROR'));
  } finally {
    installingKey.value = null;
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

const triggerLabel = type =>
  t(
    `CHATFLOW.TRIGGER.TYPE.${(type || 'on_first_message').toUpperCase()}.LABEL`
  );
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex flex-wrap items-center justify-between gap-4 px-8 py-6 border-b border-n-weak"
    >
      <div class="flex items-center gap-3">
        <span
          class="flex items-center justify-center rounded-xl shadow-lg size-11 shrink-0 bg-brand-gradient text-[#06131C] shadow-n-brand/20"
        >
          <Icon icon="i-lucide-workflow" class="size-5" />
        </span>
        <div class="flex flex-col gap-0.5">
          <h1 class="m-0 text-xl font-bold tracking-tight text-n-slate-12">
            {{ t('CHATFLOW.LIST.TITLE') }}
          </h1>
          <p class="m-0 max-w-2xl text-[13px] text-n-slate-11">
            {{ t('CHATFLOW.LIST.SUBTITLE') }}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-layout-template"
          :label="t('CHATFLOW.TEMPLATES.BROWSE')"
          @click="tab = 'templates'"
        />
        <Button
          icon="i-lucide-plus"
          :label="t('CHATFLOW.LIST.NEW')"
          data-testid="chatflow-new"
          @click="startCreate"
        />
      </div>
    </header>

    <div class="flex flex-col gap-4 px-8 pt-6">
      <div
        class="grid gap-3 grid-cols-[repeat(auto-fit,minmax(11rem,1fr))]"
        data-testid="chatflow-stats"
      >
        <div
          v-for="card in cards"
          :key="card.key"
          class="flex gap-3 items-center px-4 py-3.5 rounded-xl border border-n-weak bg-n-solid-1"
          :data-testid="`chatflow-stat-${card.key.toLowerCase()}`"
        >
          <span
            class="flex justify-center items-center rounded-lg size-9 shrink-0"
            :class="card.tone"
          >
            <Icon :icon="card.icon" class="size-[18px]" />
          </span>
          <div class="flex flex-col min-w-0">
            <span
              class="text-[10px] font-semibold tracking-wider uppercase text-n-slate-11"
            >
              {{ t(`CHATFLOW.LIST.STATS.${card.key}`) }}
            </span>
            <span class="text-lg font-bold leading-tight text-n-slate-12">
              {{ card.value }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ card.hint }}
            </span>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-3">
        <nav class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1">
          <button
            v-for="item in TABS"
            :key="item"
            type="button"
            class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
            :class="
              tab === item
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`chatflow-tab-${item}`"
            @click="tab = item"
          >
            {{ t(`CHATFLOW.LIST.TABS.${item.toUpperCase()}`) }}
            <span
              v-if="item === 'templates' && templates.length"
              class="ml-1 px-1.5 rounded-full bg-n-teal-3 text-n-teal-11 text-[10px]"
            >
              {{ templates.length }}
            </span>
          </button>
        </nav>
        <label v-if="tab === 'flows'" class="relative w-64">
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 pointer-events-none size-3.5 start-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="search"
            :placeholder="t('CHATFLOW.LIST.SEARCH')"
            class="w-full h-9 ps-8 pe-3 rounded-lg bg-n-solid-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
        </label>
      </div>
    </div>

    <!-- Modelos prontos -->
    <div v-if="tab === 'templates'" class="flex flex-col gap-4 px-8 py-6">
      <p class="m-0 text-[13px] text-n-slate-11 max-w-3xl">
        {{ t('CHATFLOW.TEMPLATES.SUBTITLE') }}
      </p>
      <div
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        data-testid="chatflow-templates"
      >
        <div
          v-for="template in templates"
          :key="template.key"
          class="flex flex-col gap-3 p-5 rounded-2xl bg-n-solid-1 border border-n-weak hover:border-n-teal-7 hover:shadow-lg transition-all"
          :data-testid="`template-${template.key}`"
        >
          <div class="flex items-start justify-between gap-2">
            <span
              class="flex items-center justify-center size-10 rounded-xl bg-brand-gradient text-[#06131C] shrink-0"
            >
              <Icon
                :icon="template.icon || 'i-lucide-workflow'"
                class="size-5"
              />
            </span>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] font-medium text-n-slate-11 bg-n-alpha-2"
            >
              {{ triggerLabel(template.trigger_type) }}
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <h3 class="text-sm font-semibold text-n-slate-12 m-0">
              {{ template.name }}
            </h3>
            <p class="text-xs text-n-slate-11 m-0 leading-relaxed">
              {{ template.description }}
            </p>
          </div>
          <div class="flex flex-wrap gap-1">
            <span
              v-for="kind in template.kinds"
              :key="kind"
              class="flex items-center justify-center size-6 rounded-md"
              :class="TONE_CLASSES[KIND_META[kind]?.tone || 'slate']"
              :title="t(`CHATFLOW.NODE.KIND.${kind.toUpperCase()}`)"
            >
              <Icon :icon="KIND_META[kind]?.icon" class="size-3.5" />
            </span>
          </div>
          <div class="flex items-center justify-between mt-auto pt-1">
            <span class="text-[11px] text-n-slate-10">
              {{
                t('CHATFLOW.LIST.NODE_COUNT', { count: template.nodes_count })
              }}
            </span>
            <Button
              size="sm"
              icon="i-lucide-copy-plus"
              :label="t('CHATFLOW.TEMPLATES.USE')"
              :is-loading="installingKey === template.key"
              :data-testid="`template-use-${template.key}`"
              @click="useTemplate(template)"
            />
          </div>
        </div>
      </div>
      <p class="m-0 text-[11px] text-n-slate-10">
        {{ t('CHATFLOW.TEMPLATES.DRAFT_NOTE') }}
      </p>
    </div>

    <div v-else class="flex-1 px-8 py-6">
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
        class="flex flex-col items-center justify-center gap-3 py-20 text-center rounded-2xl border border-dashed border-n-weak"
      >
        <span
          class="flex items-center justify-center size-14 rounded-2xl bg-brand-gradient text-[#06131C]"
        >
          <Icon icon="i-lucide-bot" class="size-7" />
        </span>
        <h3 class="text-base font-medium text-n-slate-12 m-0">
          {{ t('CHATFLOW.LIST.EMPTY_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 m-0 max-w-md">
          {{ t('CHATFLOW.LIST.EMPTY_BODY') }}
        </p>
        <Button
          variant="ghost"
          color="teal"
          icon="i-lucide-layout-template"
          :label="t('CHATFLOW.TEMPLATES.BROWSE')"
          @click="tab = 'templates'"
        />
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <button
          v-for="flow in sortedFlows"
          :key="flow.id"
          type="button"
          class="group flex flex-col gap-3 p-5 text-left rounded-2xl bg-n-solid-1 border border-n-weak hover:border-n-teal-7 hover:shadow-lg transition-all cursor-pointer"
          :data-testid="`chatflow-card-${flow.id}`"
          @click="openBuilder(flow)"
        >
          <div class="flex items-start justify-between gap-2">
            <span
              class="flex items-center justify-center size-10 rounded-xl bg-n-teal-3 text-n-teal-11 shrink-0"
            >
              <Icon icon="i-lucide-workflow" class="size-5" />
            </span>
            <div class="flex items-center gap-1.5">
              <span
                v-if="flow.test_mode"
                class="px-2 py-0.5 rounded-full text-[11px] font-medium text-n-amber-11 bg-n-amber-3"
              >
                {{ t('CHATFLOW.LIST.TESTING') }}
              </span>
              <span
                class="px-2 py-0.5 rounded-full text-[11px] font-medium capitalize"
                :class="statusTone(flow.status)"
              >
                {{ t(`CHATFLOW.STATUS.${flow.status.toUpperCase()}`) }}
              </span>
            </div>
          </div>
          <div class="flex flex-col gap-1 min-w-0">
            <h3 class="text-sm font-semibold text-n-slate-12 m-0 truncate">
              {{ flow.name }}
            </h3>
            <p class="flex items-center gap-1 text-xs text-n-slate-11 m-0">
              <Icon icon="i-lucide-zap" class="size-3" />
              {{ triggerLabel(flow.trigger_type) }}
              ·
              {{ t('CHATFLOW.LIST.NODE_COUNT', { count: flow.nodes_count }) }}
            </p>
          </div>
          <div
            class="grid grid-cols-3 gap-2 pt-3 border-t border-n-weak text-center"
          >
            <div
              v-for="key in ['started', 'completed', 'live']"
              :key="key"
              class="flex flex-col"
            >
              <span class="text-sm font-semibold text-n-slate-12 tabular-nums">
                {{ statOf(flow, key) }}
              </span>
              <span class="text-[10px] uppercase tracking-wide text-n-slate-10">
                {{ t(`CHATFLOW.LIST.CARD_STATS.${key.toUpperCase()}`) }}
              </span>
            </div>
          </div>
          <div class="flex items-center justify-end">
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
