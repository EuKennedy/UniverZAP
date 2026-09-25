<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { VueFlow, useVueFlow, MarkerType } from '@vue-flow/core';
import '@vue-flow/core/dist/style.css';
import '@vue-flow/core/dist/theme-default.css';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { LocalStorage } from 'shared/helpers/localStorage';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ChatflowNode from '../components/ChatflowNode.vue';
import ChatflowTriggerNode from '../components/ChatflowTriggerNode.vue';
import NodeEditorDrawer from '../components/NodeEditorDrawer.vue';
import TriggerConfigDrawer from '../components/TriggerConfigDrawer.vue';

const props = defineProps({
  chatflowId: { type: [String, Number], required: true },
});

// Synthetic id for the trigger entry node (not a ChatflowNode row).
const TRIGGER_ID = '__trigger__';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const FLOW_KEY = 'chatflow-builder';
const {
  onConnect,
  onNodeDragStop,
  onNodeClick,
  onNodesChange,
  onEdgesChange,
  setNodes,
  setEdges,
  addNodes,
  addEdges,
  removeNodes,
  removeEdges,
  findNode,
  fitView,
  setViewport,
  getViewport,
  onMoveEnd,
} = useVueFlow(FLOW_KEY);

const active = useMapGetter('chatflows/getActiveChatflow');

// A vista (zoom + canto) guardada por fluxo, no navegador. É preferência de
// quem está olhando, não configuração do fluxo: a moldura boa num monitor
// grande corta metade do desenho num notebook, e sincronizar levaria o problema
// junto.
const VIEWPORT_KEY = `chatflow-viewport-${props.chatflowId}`;

const readViewport = () => {
  const saved = LocalStorage.get(VIEWPORT_KEY);
  const valid =
    saved &&
    Number.isFinite(saved.x) &&
    Number.isFinite(saved.y) &&
    Number.isFinite(saved.zoom) &&
    saved.zoom > 0;
  return valid ? saved : null;
};
const selectedNodeId = ref(null);
const isSavingNode = ref(false);
const isTriggerOpen = ref(false);
const isSavingTrigger = ref(false);

// Tudo neste editor já salva sozinho — criar etapa, ligar, arrastar, mudar o
// gatilho são todos POST imediatos. O que faltava era CONTAR isso: sem nenhum
// sinal na tela, quem usa procura um botão de salvar que não existe e sai com
// medo de ter perdido o trabalho.
const savedAt = ref(null);
const markSaved = () => {
  savedAt.value = new Date();
};

const savedLabel = computed(() => {
  if (!savedAt.value) return null;
  return t('CHATFLOW.BUILDER.SAVED_AT', {
    time: savedAt.value.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    }),
  });
});

const flow = computed(() => active.value.chatflow);
const flowColor = computed(() => flow.value?.color || '#5FB89F');

// Calm, eye-friendly palette for theming a flow's edges + accents.
const FLOW_COLORS = [
  '#5FB89F',
  '#6E8AE0',
  '#C99BE0',
  '#E0A96E',
  '#E08B8B',
  '#7FB069',
  '#8593A8',
];

const PALETTE = [
  { kind: 'send_message', icon: 'i-lucide-message-square' },
  { kind: 'send_audio', icon: 'i-lucide-mic' },
  { kind: 'send_media', icon: 'i-lucide-image' },
  { kind: 'menu', icon: 'i-lucide-list-tree' },
  { kind: 'confirmation', icon: 'i-lucide-circle-check-big' },
  { kind: 'set_label', icon: 'i-lucide-tag' },
  { kind: 'assign_agent', icon: 'i-lucide-user-check' },
  { kind: 'add_to_kanban', icon: 'i-lucide-kanban-square' },
  { kind: 'webhook', icon: 'i-lucide-webhook' },
  { kind: 'end_flow', icon: 'i-lucide-flag' },
];

const DEFAULT_CONFIG = {
  send_message: { text: '' },
  send_audio: {},
  send_media: { caption: '' },
  menu: { text: '', options: [] },
  // Já vem pronta para usar: a pergunta e as palavras que a maioria das pessoas
  // responde. Uma etapa de fechamento que nasce em branco é uma etapa que
  // ninguém configura direito e que solta o cliente no meio do caminho.
  confirmation: {
    text: 'Seu problema foi resolvido?',
    resolved_keywords: ['sim', 'resolveu', 'obrigado', 'valeu'],
    unresolved_keywords: ['não', 'nao resolveu', 'quero humano', 'atendente'],
    fallback_text: 'Desculpa, não entendi. Responda com Sim ou Não.',
  },
  set_label: { label_ids: [] },
  assign_agent: {},
  add_to_kanban: {},
  webhook: { method: 'post' },
  end_flow: { actions: {} },
};

const selectedBackendNode = computed(
  () =>
    active.value.nodes.find(
      n => String(n.id) === String(selectedNodeId.value)
    ) || null
);

const mapNode = node => ({
  id: String(node.id),
  type: 'chatflow',
  position: { x: node.position_x, y: node.position_y },
  data: node,
});

const mapEdge = edge => ({
  id: String(edge.id),
  source: String(edge.source_node_id),
  target: String(edge.target_node_id),
  sourceHandle: edge.source_handle,
  animated: true,
  style: { stroke: flowColor.value, strokeWidth: 1.75 },
  markerEnd: MarkerType.ArrowClosed,
});

// The trigger is a synthetic, non-deletable entry node carrying the flow's
// trigger config. Its outgoing edge points at the start step.
// A posição do gatilho fica no trigger_config, junto do resto da configuração
// dele. Ele era sintético e vivia travado em (-40, 40): a pessoa arrastava, ele
// voltava, e o `fitView` ainda esticava a tela para alcançá-lo lá atrás.
const triggerNode = () => ({
  id: TRIGGER_ID,
  type: 'trigger',
  position: {
    x: Number(flow.value?.trigger_config?.position_x ?? -40),
    y: Number(flow.value?.trigger_config?.position_y ?? 40),
  },
  deletable: false,
  data: { chatflow: flow.value },
});

const triggerEdge = () => {
  const startId = flow.value?.start_node_id;
  if (!startId) return [];
  return [
    {
      id: 'trigger-start',
      source: TRIGGER_ID,
      target: String(startId),
      animated: true,
      deletable: false,
      style: { stroke: flowColor.value, strokeWidth: 2 },
      markerEnd: MarkerType.ArrowClosed,
    },
  ];
};

const hydrateCanvas = () => {
  setNodes([triggerNode(), ...active.value.nodes.map(mapNode)]);
  setEdges([...triggerEdge(), ...active.value.edges.map(mapEdge)]);

  // Reabre exatamente na vista em que a pessoa parou. O `fitView` que rodava
  // sempre era o que fazia o desenho "bugar" ao abrir: as posições estavam
  // salvas, mas ele reenquadrava a tela para caber TUDO — inclusive o balão do
  // gatilho, que vivia preso na origem. Quanto mais alguém organizava longe do
  // canto, mais a tela abria com tudo pequeno e espalhado.
  //
  // Só enquadra sozinho quem nunca ajustou a vista, que é o fluxo recém-criado.
  const saved = readViewport();
  if (saved) {
    setViewport(saved);
    return;
  }
  // Um quadro depois, para o Vue Flow já ter medido os balões: enquadrar antes
  // da medida calcula o zoom com tamanho zero e joga o desenho para fora.
  requestAnimationFrame(() => fitView({ padding: 0.2 }));
};

// Guardado no fim do gesto, não durante: gravar a cada pixel de arrasto encheria
// o armazenamento e não mudaria nada para quem está olhando.
const rememberViewport = () => {
  LocalStorage.set(VIEWPORT_KEY, getViewport());
};

// Arrastar o fundo e dar zoom também é ajustar a vista, e é o gesto mais comum
// de todos: sem isto a pessoa organizaria a tela e perderia o enquadramento por
// não ter movido nenhum balão.
onMoveEnd(() => rememberViewport());

// Refresh just the trigger node's data + start edge after a config change.
const refreshTrigger = () => {
  const node = findNode(TRIGGER_ID);
  if (node) node.data = { chatflow: flow.value };
  removeEdges(['trigger-start']);
  addEdges(triggerEdge());
};

onMounted(async () => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  await store.dispatch('chatflows/show', props.chatflowId);
  hydrateCanvas();
});

// --- palette: add a node ------------------------------------------------

let spawnOffset = 0;
const addNode = async kind => {
  spawnOffset += 1;
  try {
    const created = await store.dispatch('chatflows/createNode', {
      chatflowId: props.chatflowId,
      node: {
        kind,
        name: '',
        position_x: 120 + spawnOffset * 36,
        position_y: 120 + spawnOffset * 28,
        config: DEFAULT_CONFIG[kind],
      },
    });
    addNodes([mapNode(created)]);
    selectedNodeId.value = String(created.id);
    markSaved();
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.BUILDER.NODE_ERROR'));
  }
};

// --- connect two nodes (operator drags a point) -------------------------

onConnect(async params => {
  // Connecting FROM the trigger sets the flow's start step.
  if (params.source === TRIGGER_ID) {
    try {
      await store.dispatch('chatflows/update', {
        id: Number(props.chatflowId),
        start_node_id: Number(params.target),
      });
      refreshTrigger();
      markSaved();
      useAlert(t('CHATFLOW.BUILDER.START_SET'));
    } catch (error) {
      useAlert(error?.message || t('CHATFLOW.BUILDER.EDGE_ERROR'));
    }
    return;
  }
  try {
    const created = await store.dispatch('chatflows/createEdge', {
      chatflowId: props.chatflowId,
      edge: {
        source_node_id: Number(params.source),
        target_node_id: Number(params.target),
        source_handle: params.sourceHandle || 'default',
      },
    });
    addEdges([mapEdge(created)]);
    markSaved();
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.BUILDER.EDGE_ERROR'));
  }
});

// Delete via Backspace/Delete or a node's trash button. Vue Flow applies the
// removal to its own store; we mirror it to the backend here so there is a
// single persistence path (the trash button just calls removeNodes).
onNodesChange(changes => {
  changes
    .filter(c => c.type === 'remove' && c.id !== TRIGGER_ID)
    .forEach(c => {
      store.dispatch('chatflows/deleteNode', {
        chatflowId: props.chatflowId,
        nodeId: Number(c.id),
      });
      markSaved();
    });
});

onEdgesChange(changes => {
  changes
    .filter(c => c.type === 'remove' && c.id !== 'trigger-start')
    .forEach(c => {
      store.dispatch('chatflows/deleteEdge', {
        chatflowId: props.chatflowId,
        edgeId: Number(c.id),
      });
    });
});

const deleteNodeFromCanvas = id => {
  if (String(selectedNodeId.value) === String(id)) selectedNodeId.value = null;
  removeNodes([String(id)]);
};

// --- persist drag position ----------------------------------------------

onNodeDragStop(({ node }) => {
  rememberViewport();
  if (node.id === TRIGGER_ID) {
    store.dispatch('chatflows/update', {
      id: Number(props.chatflowId),
      trigger_config: {
        ...(flow.value?.trigger_config || {}),
        position_x: node.position.x,
        position_y: node.position.y,
      },
    });
    markSaved();
    return;
  }
  store.dispatch('chatflows/updateNode', {
    chatflowId: props.chatflowId,
    nodeId: Number(node.id),
    node: { position_x: node.position.x, position_y: node.position.y },
  });
  markSaved();
});

onNodeClick(({ node }) => {
  if (node.id === TRIGGER_ID) {
    selectedNodeId.value = null;
    isTriggerOpen.value = true;
    return;
  }
  isTriggerOpen.value = false;
  selectedNodeId.value = node.id;
});

// --- drawer actions ------------------------------------------------------

const saveNode = async ({ name, config }) => {
  isSavingNode.value = true;
  try {
    const updated = await store.dispatch('chatflows/updateNode', {
      chatflowId: props.chatflowId,
      nodeId: Number(selectedNodeId.value),
      node: { name, config },
    });
    const canvasNode = findNode(String(updated.id));
    if (canvasNode) canvasNode.data = updated;
    markSaved();
    useAlert(t('CHATFLOW.BUILDER.NODE_SAVED'));
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.BUILDER.NODE_ERROR'));
  } finally {
    isSavingNode.value = false;
  }
};

const removeNode = () => deleteNodeFromCanvas(selectedNodeId.value);

const setAsStart = async () => {
  await store.dispatch('chatflows/update', {
    id: Number(props.chatflowId),
    start_node_id: Number(selectedNodeId.value),
  });
  refreshTrigger();
  useAlert(t('CHATFLOW.BUILDER.START_SET'));
};

const saveTrigger = async payload => {
  isSavingTrigger.value = true;
  try {
    await store.dispatch('chatflows/update', {
      id: Number(props.chatflowId),
      ...payload,
    });
    refreshTrigger();
    isTriggerOpen.value = false;
    useAlert(t('CHATFLOW.TRIGGER.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.BUILDER.NODE_ERROR'));
  } finally {
    isSavingTrigger.value = false;
  }
};

// --- flow lifecycle ------------------------------------------------------

const toggleStatus = async () => {
  try {
    if (flow.value.status === 'active') {
      await store.dispatch('chatflows/archive', Number(props.chatflowId));
    } else {
      await store.dispatch('chatflows/activate', Number(props.chatflowId));
      useAlert(t('CHATFLOW.BUILDER.ACTIVATED'));
    }
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.message ||
        t('CHATFLOW.BUILDER.ACTIVATE_ERROR')
    );
  }
};

const changeColor = async color => {
  await store.dispatch('chatflows/update', {
    id: Number(props.chatflowId),
    color,
  });
  // Re-apply edge strokes with the new accent (no viewport jump).
  setEdges([...triggerEdge(), ...active.value.edges.map(mapEdge)]);
};

// --- test mode -----------------------------------------------------------

const isTestPopupOpen = ref(false);
const testPhone = ref('');
const isTestActive = computed(() => Boolean(flow.value?.test_mode));

const openTestPopup = () => {
  testPhone.value = flow.value?.test_phone || '';
  isTestPopupOpen.value = true;
};

const startTest = async () => {
  const phone = testPhone.value.trim();
  if (!phone) return;
  try {
    await store.dispatch('chatflows/test', {
      id: Number(props.chatflowId),
      phone,
    });
    isTestPopupOpen.value = false;
    useAlert(t('CHATFLOW.TEST.STARTED'));
  } catch (error) {
    useAlert(error?.message || t('CHATFLOW.TEST.ERROR'));
  }
};

const stopTest = async () => {
  await store.dispatch('chatflows/stopTest', Number(props.chatflowId));
  useAlert(t('CHATFLOW.TEST.STOPPED'));
};

const goBack = () => router.push(accountScopedRoute('chatflow_index'));
</script>

<template>
  <div class="flex w-full h-full overflow-hidden bg-n-background">
    <!-- Options panel — lives on the LEFT -->
    <TriggerConfigDrawer
      v-if="isTriggerOpen && flow"
      :chatflow="flow"
      :is-saving="isSavingTrigger"
      @save="saveTrigger"
      @close="isTriggerOpen = false"
    />
    <NodeEditorDrawer
      v-else-if="selectedBackendNode"
      :key="selectedBackendNode.id"
      :node="selectedBackendNode"
      :is-start="flow?.start_node_id === selectedBackendNode.id"
      :is-saving="isSavingNode"
      @save="saveNode"
      @remove="removeNode"
      @set-start="setAsStart"
      @close="selectedNodeId = null"
    />

    <div class="flex flex-col flex-1 min-w-0">
      <header
        class="flex items-center justify-between gap-3 px-5 h-14 border-b border-n-weak bg-n-solid-1 z-10"
      >
        <div class="flex items-center gap-3 min-w-0">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-arrow-left"
            @click="goBack"
          />
          <h1 class="text-sm font-semibold text-n-slate-12 m-0 truncate">
            {{ flow?.name }}
          </h1>
          <span
            v-if="flow"
            class="px-2 py-0.5 rounded-full text-[11px] font-medium capitalize"
            :class="
              flow.status === 'active'
                ? 'text-n-teal-11 bg-n-teal-3'
                : 'text-n-amber-11 bg-n-amber-3'
            "
          >
            {{ t(`CHATFLOW.STATUS.${(flow.status || 'draft').toUpperCase()}`) }}
          </span>
          <!-- Tudo aqui já salva sozinho. Sem este aviso, quem usa procura um
            botão de salvar que não existe e sai da tela com medo de ter perdido
            o trabalho. -->
          <span
            v-if="savedLabel"
            class="text-[11px] text-n-slate-10 tabular-nums"
            data-testid="chatflow-saved-at"
          >
            {{ savedLabel }}
          </span>
        </div>
        <div
          v-if="isTestActive"
          class="flex items-center gap-2 px-2.5 h-8 rounded-lg bg-n-amber-3 text-n-amber-11 text-xs font-medium"
        >
          <span class="relative flex size-2">
            <span
              class="absolute inline-flex h-full w-full rounded-full bg-n-amber-9 opacity-75 motion-safe:animate-ping"
            />
            <span
              class="relative inline-flex rounded-full size-2 bg-n-amber-9"
            />
          </span>
          {{ t('CHATFLOW.TEST.ACTIVE', { phone: flow.test_phone }) }}
          <button
            type="button"
            class="ml-1 underline cursor-pointer hover:text-n-amber-12"
            @click="stopTest"
          >
            {{ t('CHATFLOW.TEST.STOP') }}
          </button>
        </div>
        <Button
          v-else-if="flow"
          variant="ghost"
          color="slate"
          icon="i-lucide-flask-conical"
          :label="t('CHATFLOW.TEST.BUTTON')"
          @click="openTestPopup"
        />
        <div v-if="flow" class="flex items-center gap-1.5 mr-1">
          <button
            v-for="color in FLOW_COLORS"
            :key="color"
            type="button"
            class="size-5 rounded-full cursor-pointer transition-transform hover:scale-110"
            :class="
              flowColor === color
                ? 'ring-2 ring-offset-2 ring-offset-n-solid-1 ring-n-slate-9'
                : ''
            "
            :style="{ backgroundColor: color }"
            :aria-label="t('CHATFLOW.BUILDER.COLOR')"
            @click="changeColor(color)"
          />
        </div>
        <Button
          v-if="flow"
          :color="flow.status === 'active' ? 'amber' : 'teal'"
          :icon="flow.status === 'active' ? 'i-lucide-pause' : 'i-lucide-play'"
          :label="
            flow.status === 'active'
              ? t('CHATFLOW.BUILDER.ARCHIVE')
              : t('CHATFLOW.BUILDER.ACTIVATE')
          "
          @click="toggleStatus"
        />
      </header>

      <div class="flex flex-1 min-h-0">
        <!-- Infinite canvas -->
        <div class="relative flex-1 min-w-0">
          <VueFlow
            :id="FLOW_KEY"
            :default-viewport="{ zoom: 0.9 }"
            :min-zoom="0.2"
            :max-zoom="2"
            :delete-key-code="['Backspace', 'Delete']"
            fit-view-on-init
            class="bg-n-background [background-image:radial-gradient(circle,_rgba(148,163,184,0.18)_1px,_transparent_1px)] [background-size:22px_22px]"
          >
            <template #node-trigger="nodeProps">
              <ChatflowTriggerNode
                :data="nodeProps.data"
                :selected="isTriggerOpen"
              />
            </template>
            <template #node-chatflow="nodeProps">
              <ChatflowNode
                :id="nodeProps.id"
                :data="nodeProps.data"
                :selected="nodeProps.id === selectedNodeId"
                @delete="deleteNodeFromCanvas(nodeProps.id)"
              />
            </template>
          </VueFlow>
        </div>

        <!-- Palette (far right) -->
        <nav
          class="flex flex-col gap-1 w-44 shrink-0 p-2 border-l border-n-weak bg-n-solid-1 overflow-auto"
        >
          <p
            class="px-2 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10 m-0"
          >
            {{ t('CHATFLOW.BUILDER.PALETTE') }}
          </p>
          <button
            v-for="item in PALETTE"
            :key="item.kind"
            type="button"
            class="flex items-center gap-2 px-2.5 h-9 rounded-lg text-xs text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer text-left"
            @click="addNode(item.kind)"
          >
            <Icon :icon="item.icon" class="size-4 text-n-slate-11" />
            {{ t(`CHATFLOW.NODE.KIND.${item.kind.toUpperCase()}`) }}
          </button>
        </nav>
      </div>
    </div>

    <!-- Test mode popup -->
    <div
      v-if="isTestPopupOpen"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm"
      @click.self="isTestPopupOpen = false"
    >
      <div
        class="w-[400px] rounded-2xl bg-n-solid-1 border border-n-weak shadow-2xl p-6 flex flex-col gap-4"
      >
        <div class="flex items-center gap-3">
          <span
            class="flex items-center justify-center size-10 rounded-xl bg-n-amber-3 text-n-amber-11"
          >
            <Icon icon="i-lucide-flask-conical" class="size-5" />
          </span>
          <div class="flex flex-col">
            <h3 class="text-sm font-semibold text-n-slate-12 m-0">
              {{ t('CHATFLOW.TEST.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-11 m-0">
              {{ t('CHATFLOW.TEST.SUBTITLE') }}
            </p>
          </div>
        </div>
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CHATFLOW.TEST.PHONE') }}
          </span>
          <input
            v-model="testPhone"
            v-focus
            type="tel"
            :placeholder="t('CHATFLOW.TEST.PHONE_PLACEHOLDER')"
            class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
            @keydown.enter="startTest"
          />
        </label>
        <div class="flex items-center justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            :label="t('CHATFLOW.TEST.CANCEL')"
            @click="isTestPopupOpen = false"
          />
          <Button
            color="amber"
            icon="i-lucide-play"
            :label="t('CHATFLOW.TEST.START')"
            @click="startTest"
          />
        </div>
      </div>
    </div>
  </div>
</template>
