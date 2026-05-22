<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversation: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close', 'attached']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const funnels = computed(() => getters['funnels/getFunnels'].value || []);
const selectedFunnelId = ref(null);
const hoveredStageId = ref(null);
const attachingStageId = ref(null);
const justAttachedStageId = ref(null);
const isLoadingFunnels = ref(false);

const selectedFunnel = computed(
  () => funnels.value.find(f => f.id === selectedFunnelId.value) || null
);

const stages = computed(() => {
  const list = selectedFunnel.value?.stages || [];
  return [...list].sort((a, b) => a.position - b.position);
});

const contactName = computed(
  () =>
    props.conversation?.meta?.sender?.name ||
    props.conversation?.contact?.name ||
    ''
);

const conversationDisplayId = computed(
  () => props.conversation?.display_id || props.conversation?.id
);

const close = () => emit('close');

const ensureFunnelsLoaded = async () => {
  if (funnels.value.length) {
    if (!selectedFunnelId.value) selectedFunnelId.value = funnels.value[0].id;
    return;
  }
  isLoadingFunnels.value = true;
  try {
    await store.dispatch('funnels/get');
    if (funnels.value.length && !selectedFunnelId.value) {
      selectedFunnelId.value = funnels.value[0].id;
    }
  } finally {
    isLoadingFunnels.value = false;
  }
};

onMounted(ensureFunnelsLoaded);
watch(
  () => props.show,
  v => {
    if (v) {
      ensureFunnelsLoaded();
      justAttachedStageId.value = null;
    }
  }
);

const stageGradient = stage => {
  const base = stage?.color || '#6366f1';
  return `linear-gradient(135deg, ${base}1f 0%, ${base}0a 100%)`;
};

const attach = async stage => {
  if (attachingStageId.value) return;
  attachingStageId.value = stage.id;
  try {
    await store.dispatch('conversations/attachToKanban', {
      conversationId: props.conversation.id,
      funnelStageId: stage.id,
    });
    justAttachedStageId.value = stage.id;
    useAlert(t('CONVERSATION.KANBAN_ATTACH.SUCCESS', { stage: stage.name }));
    emit('attached', { stage });
    await nextTick();
    setTimeout(close, 750);
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.message ||
        t('CONVERSATION.KANBAN_ATTACH.ERROR')
    );
  } finally {
    attachingStageId.value = null;
  }
};
</script>

<template>
  <woot-modal
    :show="props.show"
    size="full"
    :on-close="close"
    @update:show="value => !value && close()"
  >
    <div class="flex flex-col h-full w-full bg-n-background text-n-slate-12">
      <!-- HEADER -->
      <header
        class="relative flex items-center justify-between flex-shrink-0 gap-6 px-8 py-5 border-b border-n-weak bg-gradient-to-b from-n-alpha-1 to-transparent"
      >
        <div class="flex items-center gap-4 min-w-0">
          <div
            class="size-11 rounded-xl bg-gradient-to-br from-n-iris-9 to-n-iris-11 flex items-center justify-center shadow-lg shadow-n-iris-9/20 flex-shrink-0"
          >
            <span class="i-lucide-layout-grid size-5 text-white" />
          </div>
          <div class="flex flex-col gap-0.5 min-w-0">
            <h2 class="text-[20px] font-semibold tracking-tight leading-tight">
              {{ t('CONVERSATION.KANBAN_ATTACH.TITLE') }}
            </h2>
            <p
              v-if="contactName"
              class="text-[13px] text-n-slate-11 truncate flex items-center gap-1.5"
            >
              <span class="i-lucide-user size-3 text-n-slate-10" />
              <span>{{ contactName }}</span>
              <span v-if="conversationDisplayId" class="text-n-slate-10">
                {{
                  t('CONVERSATION.KANBAN_ATTACH.ID_PREFIX', {
                    id: conversationDisplayId,
                  })
                }}
              </span>
            </p>
            <p v-else class="text-[13px] text-n-slate-11">
              {{ t('CONVERSATION.KANBAN_ATTACH.SUBTITLE') }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="size-9 rounded-lg flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 transition"
          :aria-label="t('CONVERSATION.KANBAN_ATTACH.CLOSE')"
          @click="close"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>

      <!-- LOADING STATE -->
      <section
        v-if="isLoadingFunnels"
        class="flex-1 flex flex-col items-center justify-center gap-3"
      >
        <span
          class="i-lucide-loader-circle size-6 animate-spin text-n-slate-9"
        />
        <p class="text-sm text-n-slate-11">
          {{ t('CONVERSATION.KANBAN_ATTACH.LOADING') }}
        </p>
      </section>

      <!-- EMPTY STATE -->
      <section
        v-else-if="!funnels.length"
        class="flex-1 flex flex-col items-center justify-center gap-5 px-8 text-center"
      >
        <div
          class="size-16 rounded-2xl bg-n-alpha-1 flex items-center justify-center"
        >
          <span class="i-lucide-layers size-7 text-n-slate-10" />
        </div>
        <div class="flex flex-col gap-1.5 max-w-md">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('CONVERSATION.KANBAN_ATTACH.EMPTY_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-relaxed">
            {{ t('CONVERSATION.KANBAN_ATTACH.EMPTY') }}
          </p>
        </div>
      </section>

      <!-- BOARD -->
      <section v-else class="flex flex-1 min-h-0">
        <!-- Funnel rail -->
        <aside
          class="w-72 flex-shrink-0 border-r border-n-weak overflow-y-auto p-4 flex flex-col gap-1 bg-n-alpha-1"
        >
          <p
            class="text-[10px] uppercase tracking-[0.12em] text-n-slate-10 px-2 pt-1 pb-3"
          >
            {{ t('CONVERSATION.KANBAN_ATTACH.FUNNELS') }}
            <span class="text-n-slate-9 ml-1">{{ funnels.length }}</span>
          </p>
          <button
            v-for="funnel in funnels"
            :key="funnel.id"
            type="button"
            class="group text-left px-3 py-2.5 rounded-lg text-sm transition-all duration-200 relative overflow-hidden"
            :class="
              funnel.id === selectedFunnelId
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm border border-n-weak'
                : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
            "
            @click="selectedFunnelId = funnel.id"
          >
            <div class="flex items-center gap-2">
              <span
                class="size-1.5 rounded-full flex-shrink-0 transition"
                :class="
                  funnel.id === selectedFunnelId
                    ? 'bg-n-iris-9'
                    : 'bg-n-slate-9 group-hover:bg-n-slate-10'
                "
              />
              <span class="truncate font-medium">{{ funnel.name }}</span>
              <span class="ml-auto text-[10px] text-n-slate-10 tabular-nums">
                {{ (funnel.stages || []).length }}
              </span>
            </div>
            <p
              v-if="funnel.description"
              class="text-[11px] text-n-slate-10 truncate mt-0.5 ml-3.5"
            >
              {{ funnel.description }}
            </p>
          </button>
        </aside>

        <!-- Stages -->
        <main class="flex-1 overflow-x-auto overflow-y-hidden bg-n-background">
          <div class="flex items-stretch gap-5 px-8 py-6 h-full min-w-min">
            <article
              v-for="stage in stages"
              :key="stage.id"
              class="w-[280px] flex-shrink-0 rounded-2xl border border-n-weak flex flex-col overflow-hidden transition-all duration-200 cursor-pointer"
              :class="[
                hoveredStageId === stage.id
                  ? 'shadow-2xl shadow-black/40 border-n-strong scale-[1.02]'
                  : 'shadow-md shadow-black/10',
                justAttachedStageId === stage.id && 'ring-2 ring-n-teal-9',
              ]"
              :style="{ background: stageGradient(stage) }"
              @mouseenter="hoveredStageId = stage.id"
              @mouseleave="hoveredStageId = null"
              @click="attach(stage)"
            >
              <header
                class="flex items-center justify-between px-5 py-4 border-b border-white/5"
              >
                <div class="flex items-center gap-2.5 min-w-0">
                  <span
                    class="size-2.5 rounded-full flex-shrink-0 ring-2 ring-black/20"
                    :style="{ backgroundColor: stage.color || '#6366f1' }"
                  />
                  <span
                    class="text-[13px] font-semibold text-n-slate-12 truncate tracking-tight"
                  >
                    {{ stage.name }}
                  </span>
                </div>
                <span
                  class="text-[10px] uppercase tracking-wide text-n-slate-10 tabular-nums"
                >
                  {{ stage.position }}
                </span>
              </header>
              <div
                class="flex-1 px-5 py-5 flex flex-col items-center justify-center gap-3"
              >
                <span
                  v-if="justAttachedStageId === stage.id"
                  class="flex items-center justify-center size-12 rounded-full bg-n-teal-9/20"
                >
                  <span class="i-lucide-check size-6 text-n-teal-11" />
                </span>
                <span
                  v-else-if="attachingStageId === stage.id"
                  class="i-lucide-loader-circle size-7 animate-spin text-n-iris-11"
                />
                <span
                  v-else-if="hoveredStageId === stage.id"
                  class="i-lucide-plus size-8 text-n-iris-11 transition-transform duration-200 scale-110"
                />
                <span
                  v-else
                  class="i-lucide-plus size-7 text-n-slate-10 transition"
                />
                <p
                  class="text-[12px] text-n-slate-11 text-center leading-snug max-w-[180px]"
                >
                  {{
                    justAttachedStageId === stage.id
                      ? t('CONVERSATION.KANBAN_ATTACH.DONE')
                      : attachingStageId === stage.id
                        ? t('CONVERSATION.KANBAN_ATTACH.ATTACHING')
                        : t('CONVERSATION.KANBAN_ATTACH.MOVE_HERE')
                  }}
                </p>
              </div>
            </article>
            <div
              v-if="!stages.length"
              class="flex-1 flex items-center justify-center"
            >
              <p class="text-sm text-n-slate-11">
                {{ t('CONVERSATION.KANBAN_ATTACH.NO_STAGES') }}
              </p>
            </div>
          </div>
        </main>
      </section>
    </div>
  </woot-modal>
</template>
