<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  KIND_META,
  TONE_CLASSES,
  nodeHandles,
  nodeSummary,
} from '../helpers/nodeKinds';
import { rateTone } from '../helpers/funnel';

// Custom Vue Flow node: one card = one "etapa". The target handle (left) is
// where an incoming edge lands. Source handles (right) are the connection
// POINTS the operator drags to the next card — a single `default` point for
// linear steps, or one named point per exit (menu options, se/senão, A/B,
// pergunta válida/inválida…). The handle `id` is persisted as the edge
// `source_handle`; the list of exits lives in helpers/nodeKinds.js.
const props = defineProps({
  data: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  // Funil desta etapa (entraram/avançaram/esperando/saíram), quando ligado.
  funnel: { type: Object, default: null },
  // Simulação: a etapa por onde a conversa simulada passou / onde parou.
  simulation: { type: String, default: null },
  context: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['delete']);

const { t } = useI18n();

const kind = computed(() => props.data.kind);
const meta = computed(() => KIND_META[kind.value] || KIND_META.send_message);
const handles = computed(() => nodeHandles(props.data, t));
const named = computed(() => handles.value.some(h => h.label !== null));

const title = computed(
  () => props.data.name || t(`CHATFLOW.NODE.KIND.${kind.value.toUpperCase()}`)
);

const summary = computed(() => nodeSummary(props.data, t, props.context));

const ringClass = computed(() => {
  if (props.selected)
    return 'border-n-teal-7 shadow-md ring-1 ring-n-teal-6/40';
  if (props.simulation === 'current')
    return 'border-n-amber-8 shadow-md ring-2 ring-n-amber-7/50';
  if (props.simulation === 'visited')
    return 'border-n-teal-8 ring-1 ring-n-teal-7/40';
  return 'border-n-weak hover:border-n-slate-6';
});
</script>

<template>
  <div
    class="group relative w-64 rounded-2xl border bg-n-solid-1 shadow-sm transition-all"
    :class="ringClass"
    :data-testid="`chatflow-node-${kind}`"
  >
    <!-- Delete affordance (hover) -->
    <button
      type="button"
      class="absolute -top-2.5 -right-2.5 z-10 inline-flex items-center justify-center size-6 rounded-full bg-n-solid-2 text-n-slate-11 ring-1 ring-n-weak shadow-sm opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer hover:bg-n-ruby-9 hover:text-white"
      :aria-label="t('CHATFLOW.NODE.DELETE')"
      :title="t('CHATFLOW.NODE.DELETE')"
      @click.stop="emit('delete')"
    >
      <Icon icon="i-lucide-trash-2" class="size-3.5" />
    </button>

    <!-- Funil: quantos entraram e quantos seguiram. -->
    <div
      v-if="funnel"
      class="absolute -top-3 left-3 z-10 flex items-center gap-1.5 px-2 h-6 rounded-full bg-n-solid-2 ring-1 ring-n-weak shadow-sm text-[11px] font-medium tabular-nums"
      data-testid="node-funnel"
    >
      <Icon icon="i-lucide-users" class="size-3 text-n-slate-10" />
      <span class="text-n-slate-12">{{ funnel.entered }}</span>
      <span v-if="funnel.rate !== null" :class="rateTone(funnel.rate)">
        {{ t('CHATFLOW.FUNNEL.RATE', { rate: funnel.rate }) }}
      </span>
      <span v-if="funnel.waiting" class="text-n-amber-11">
        {{ t('CHATFLOW.FUNNEL.WAITING_SHORT', { count: funnel.waiting }) }}
      </span>
    </div>

    <!-- Entry point -->
    <Handle
      type="target"
      :position="Position.Left"
      class="!size-3 !bg-n-slate-8 !border-2 !border-n-solid-1"
    />

    <div class="flex items-center gap-2.5 px-3.5 pt-3.5">
      <span
        class="flex items-center justify-center size-8 rounded-lg shrink-0"
        :class="TONE_CLASSES[meta.tone]"
      >
        <Icon :icon="meta.icon" class="size-4" />
      </span>
      <div class="flex flex-col min-w-0">
        <p class="text-sm font-semibold text-n-slate-12 m-0 truncate">
          {{ title }}
        </p>
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10 m-0">
          {{ t(`CHATFLOW.NODE.KIND.${kind.toUpperCase()}`) }}
        </p>
      </div>
    </div>

    <p
      v-if="summary"
      class="px-3.5 pt-2 pb-3 text-xs text-n-slate-11 m-0 line-clamp-3 whitespace-pre-line"
    >
      {{ summary }}
    </p>
    <div v-else class="pb-3" />

    <!-- Saídas nomeadas: uma porta por destino, com o nome à vista. Sem o
      rótulo, as bolinhas ficam idênticas e ligar a errada é questão de tempo. -->
    <div v-if="named" class="flex flex-col border-t border-n-weak">
      <div
        v-for="(exit, index) in handles"
        :key="exit.handle"
        class="relative flex items-center gap-2 px-3.5 py-2 text-xs text-n-slate-12 border-b border-n-weak last:border-b-0"
        :data-testid="`node-exit-${exit.handle}`"
      >
        <span
          v-if="kind === 'menu'"
          class="flex items-center justify-center size-5 rounded-md bg-n-alpha-2 text-[10px] font-bold text-n-slate-11"
        >
          {{ index + 1 }}
        </span>
        <span v-else class="size-2 rounded-full" :class="exit.dot" />
        <span class="truncate">{{ exit.label }}</span>
        <Handle
          :id="exit.handle"
          type="source"
          :position="Position.Right"
          class="!size-3 !border-2 !border-n-solid-1"
          :class="exit.handleClass"
        />
      </div>
    </div>

    <!-- Linear nodes: single forward point -->
    <Handle
      v-else-if="handles.length"
      id="default"
      type="source"
      :position="Position.Right"
      class="!size-3 !bg-n-teal-8 !border-2 !border-n-solid-1"
    />
  </div>
</template>
