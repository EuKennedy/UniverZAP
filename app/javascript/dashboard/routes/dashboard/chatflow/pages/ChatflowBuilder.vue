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
import Button from 'dashboard/components-next/button/Button.vue';
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
} = useVueFlow(FLOW_KEY);

const active = useMapGetter('chatflows/getActiveChatflow');
const selectedNodeId = ref(null);
const isSavingNode = ref(false);
const isTriggerOpen = ref(false);
const isSavingTrigger = ref(false);

const flow = computed(() => active.value.chatflow);

const PALETTE = [
  { kind: 'send_message', icon: 'i-lucide-message-square' },
  { kind: 'send_audio', icon: 'i-lucide-mic' },
  { kind: 'send_media', icon: 'i-lucide-image' },
  { kind: 'menu', icon: 'i-lucide-list-tree' },
  { kind: 'set_label', icon: 'i-lucide-tag' },
  { kind: 'end_flow', icon: 'i-lucide-flag' },
];

const DEFAULT_CONFIG = {
  send_message: { text: '' },
  send_audio: {},
  send_media: { caption: '' },
  menu: { text: '', options: [] },
  set_label: { label_ids: [] },
  end_flow: {},
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
  style: { stroke: '#94A3B8', strokeWidth: 1.75 },
  markerEnd: MarkerType.ArrowClosed,
});

// The trigger is a synthetic, non-deletable entry node carrying the flow's
// trigger config. Its outgoing edge points at the start step.
const triggerNode = () => ({
  id: TRIGGER_ID,
  type: 'trigger',
  position: { x: -40, y: 40 },
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
      style: { stroke: '#5FB89F', strokeWidth: 2 },
      markerEnd: MarkerType.ArrowClosed,
    },
  ];
};

const hydrateCanvas = () => {
  setNodes([triggerNode(), ...active.value.nodes.map(mapNode)]);
  setEdges([...triggerEdge(), ...active.value.edges.map(mapEdge)]);
  setTimeout(() => fitView({ padding: 0.2 }), 50);
};

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
  if (node.id === TRIGGER_ID) return; // synthetic, position not persisted
  store.dispatch('chatflows/updateNode', {
    chatflowId: props.chatflowId,
    nodeId: Number(node.id),
    node: { position_x: node.position.x, position_y: node.position.y },
  });
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
        <!-- Palette -->
        <nav
          class="flex flex-col gap-1 w-44 shrink-0 p-2 border-r border-n-weak bg-n-solid-1 overflow-auto"
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
            <fluent-icon
              :icon="item.icon.replace('i-lucide-', '')"
              size="16"
              class="text-n-slate-11"
            />
            {{ t(`CHATFLOW.NODE.KIND.${item.kind.toUpperCase()}`) }}
          </button>
        </nav>

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
      </div>
    </div>
  </div>
</template>
