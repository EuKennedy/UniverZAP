<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversationId: { type: [Number, String], required: true },
});

const emit = defineEmits(['close', 'attached']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const funnels = computed(() => getters['funnels/getFunnels'].value || []);
const selectedFunnelId = ref(null);
const attaching = ref(false);

const selectedFunnel = computed(() =>
  funnels.value.find(f => f.id === selectedFunnelId.value)
);

const stages = computed(() => {
  const list = selectedFunnel.value?.stages || [];
  return [...list].sort((a, b) => a.position - b.position);
});

const close = () => emit('close');

const ensureFunnelsLoaded = async () => {
  if (funnels.value.length === 0) {
    await store.dispatch('funnels/index');
  }
  if (!selectedFunnelId.value && funnels.value.length) {
    selectedFunnelId.value = funnels.value[0].id;
  }
};

onMounted(ensureFunnelsLoaded);
watch(
  () => props.show,
  val => {
    if (val) ensureFunnelsLoaded();
  }
);

const attach = async stage => {
  if (attaching.value) return;
  attaching.value = true;
  try {
    await store.dispatch('conversations/attachToKanban', {
      conversationId: props.conversationId,
      funnelStageId: stage.id,
    });
    useAlert(t('CONVERSATION.KANBAN_ATTACH.SUCCESS', { stage: stage.name }));
    emit('attached', { stage });
    close();
  } catch (error) {
    useAlert(error?.message || t('CONVERSATION.KANBAN_ATTACH.ERROR'));
  } finally {
    attaching.value = false;
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
    <div class="flex flex-col h-full w-full bg-n-background">
      <header
        class="flex items-center justify-between flex-shrink-0 gap-4 px-8 py-5 border-b border-n-weak"
      >
        <div class="flex flex-col gap-0.5 min-w-0">
          <h2 class="text-lg font-semibold text-n-slate-12 tracking-tight">
            {{ t('CONVERSATION.KANBAN_ATTACH.TITLE') }}
          </h2>
          <p class="text-[12px] text-n-slate-11">
            {{ t('CONVERSATION.KANBAN_ATTACH.SUBTITLE') }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          size="sm"
          ghost
          slate
          :aria-label="t('CONVERSATION.KANBAN_ATTACH.CLOSE')"
          @click="close"
        />
      </header>

      <section
        v-if="!funnels.length"
        class="flex-1 flex flex-col items-center justify-center gap-3 px-8 text-center"
      >
        <span class="i-lucide-layers size-10 text-n-slate-9" />
        <p class="text-sm text-n-slate-11 max-w-sm">
          {{ t('CONVERSATION.KANBAN_ATTACH.EMPTY') }}
        </p>
      </section>

      <section v-else class="flex flex-1 min-h-0">
        <aside
          class="w-64 flex-shrink-0 border-r border-n-weak overflow-y-auto p-4 flex flex-col gap-1"
        >
          <p class="text-[11px] uppercase tracking-wide text-n-slate-10 mb-2">
            {{ t('CONVERSATION.KANBAN_ATTACH.FUNNELS') }}
          </p>
          <button
            v-for="funnel in funnels"
            :key="funnel.id"
            type="button"
            class="text-left px-3 py-2 rounded-md text-sm transition-colors"
            :class="
              funnel.id === selectedFunnelId
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="selectedFunnelId = funnel.id"
          >
            {{ funnel.name }}
          </button>
        </aside>

        <main class="flex-1 overflow-x-auto overflow-y-hidden">
          <div class="flex items-stretch gap-4 px-6 py-5 h-full min-w-min">
            <div
              v-for="stage in stages"
              :key="stage.id"
              class="w-72 flex-shrink-0 rounded-xl bg-n-alpha-1 border border-n-weak flex flex-col"
            >
              <header
                class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
              >
                <span
                  class="inline-flex items-center gap-2 text-sm font-medium text-n-slate-12 truncate"
                >
                  <span
                    class="size-2 rounded-full"
                    :style="{ backgroundColor: stage.color || '#6366f1' }"
                  />
                  {{ stage.name }}
                </span>
              </header>
              <div class="flex-1 p-4">
                <Button
                  :label="t('CONVERSATION.KANBAN_ATTACH.MOVE_HERE')"
                  size="sm"
                  faded
                  slate
                  class="w-full"
                  :is-loading="attaching"
                  @click="attach(stage)"
                />
              </div>
            </div>
            <p
              v-if="!stages.length"
              class="text-sm text-n-slate-11 self-center"
            >
              {{ t('CONVERSATION.KANBAN_ATTACH.NO_STAGES') }}
            </p>
          </div>
        </main>
      </section>
    </div>
  </woot-modal>
</template>
