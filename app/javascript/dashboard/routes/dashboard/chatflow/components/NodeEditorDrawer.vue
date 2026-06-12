<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { DirectUpload } from 'activestorage';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

// Side panel that edits one node's config. Shape of `config` depends on the
// node kind; we keep an editable local copy and emit a normalized patch on
// save. Media (image/audio/video/doc) is uploaded straight to ActiveStorage
// via the account-scoped chatflow endpoint, and the resulting signed_id is
// stored in config.attachment — exactly what MessageBuilder consumes.
const props = defineProps({
  node: { type: Object, required: true },
  isStart: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'remove', 'setStart', 'close']);

const { t } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');
const labels = useMapGetter('labels/getLabels');
const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');
const funnels = useMapGetter('funnels/getFunnels');

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('funnels/get');
});

const name = ref('');
const config = ref({});
const isUploading = ref(false);

const kind = computed(() => props.node.kind);
const isMenu = computed(() => kind.value === 'menu');

const genId = () =>
  `opt_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

watch(
  () => props.node,
  node => {
    name.value = node.name || '';
    config.value = JSON.parse(JSON.stringify(node.config || {}));
    if (isMenu.value && !Array.isArray(config.value.options)) {
      config.value.options = [];
    }
  },
  { immediate: true }
);

const options = computed({
  get: () => config.value.options || [],
  set: val => {
    config.value.options = val;
  },
});

const addOption = () => {
  options.value = [...options.value, { label: '', value: genId() }];
};
const removeOption = index => {
  options.value = options.value.filter((_, i) => i !== index);
};

const labelIds = computed({
  get: () => config.value.label_ids || [],
  set: val => {
    config.value.label_ids = val;
  },
});
const toggleLabel = id => {
  labelIds.value = labelIds.value.includes(id)
    ? labelIds.value.filter(l => l !== id)
    : [...labelIds.value, id];
};

// add_to_kanban: stages come from the funnel the operator picks.
const selectedFunnel = computed(() =>
  funnels.value.find(f => f.id === config.value.funnel_id)
);
const funnelStages = computed(() => selectedFunnel.value?.stages || []);
const onFunnelChange = () => {
  config.value.funnel_stage_id = null;
};

// end_flow: optional resolve-on-finish toggle.
const resolveOnEnd = computed({
  get: () => Boolean(config.value.actions?.resolve),
  set: val => {
    config.value.actions = { ...(config.value.actions || {}), resolve: val };
  },
});

const HTTP_METHODS = [
  { value: 'post', label: 'POST' },
  { value: 'get', label: 'GET' },
  { value: 'put', label: 'PUT' },
];

const uploadMedia = event => {
  const file = event.target.files?.[0];
  if (!file) return;
  isUploading.value = true;
  const upload = new DirectUpload(
    file,
    `/api/v1/accounts/${accountId.value}/chatflow_direct_uploads`,
    {
      directUploadWillCreateBlobWithXHR: xhr => {
        xhr.setRequestHeader(
          'api_access_token',
          currentUser.value.access_token
        );
      },
    }
  );
  upload.create((error, blob) => {
    isUploading.value = false;
    if (error) {
      useAlert(t('CHATFLOW.EDITOR.UPLOAD_ERROR'));
      return;
    }
    config.value = {
      ...config.value,
      attachment: blob.signed_id,
      attachment_name: blob.filename,
    };
  });
};

const clearMedia = () => {
  const { attachment, attachment_name: attachmentName, ...rest } = config.value;
  config.value = rest;
};

const save = () => {
  emit('save', { name: name.value.trim(), config: config.value });
};
</script>

<template>
  <aside
    class="flex flex-col w-[360px] h-full bg-n-solid-1 border-r border-n-weak shadow-xl"
  >
    <header
      class="flex items-center justify-between px-4 h-14 border-b border-n-weak"
    >
      <h3 class="text-sm font-semibold text-n-slate-12 m-0">
        {{ t(`CHATFLOW.NODE.KIND.${kind.toUpperCase()}`) }}
      </h3>
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-x"
        @click="emit('close')"
      />
    </header>

    <div class="flex-1 overflow-auto px-4 py-4 flex flex-col gap-4">
      <!-- Name -->
      <label class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">{{
          t('CHATFLOW.EDITOR.NAME')
        }}</span>
        <input
          v-model="name"
          type="text"
          :placeholder="t('CHATFLOW.EDITOR.NAME_PLACEHOLDER')"
          class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
        />
      </label>

      <!-- Message / Menu text -->
      <label
        v-if="['send_message', 'menu'].includes(kind)"
        class="flex flex-col gap-1.5"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{
            isMenu
              ? t('CHATFLOW.EDITOR.MENU_PROMPT')
              : t('CHATFLOW.EDITOR.MESSAGE_TEXT')
          }}
        </span>
        <textarea
          v-model="config.text"
          rows="4"
          :placeholder="t('CHATFLOW.EDITOR.MESSAGE_PLACEHOLDER')"
          class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 resize-y focus:outline-none focus:border-n-teal-8"
        />
      </label>

      <!-- Media caption -->
      <label v-if="kind === 'send_media'" class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">{{
          t('CHATFLOW.EDITOR.CAPTION')
        }}</span>
        <textarea
          v-model="config.caption"
          rows="3"
          :placeholder="t('CHATFLOW.EDITOR.CAPTION_PLACEHOLDER')"
          class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 resize-y focus:outline-none focus:border-n-teal-8"
        />
      </label>

      <!-- Media upload (message optional, audio/media required) -->
      <div
        v-if="['send_message', 'send_audio', 'send_media'].includes(kind)"
        class="flex flex-col gap-1.5"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{
            kind === 'send_audio'
              ? t('CHATFLOW.EDITOR.AUDIO')
              : t('CHATFLOW.EDITOR.MEDIA')
          }}
          <span v-if="kind === 'send_message'" class="text-n-slate-10">
            {{ t('CHATFLOW.EDITOR.OPTIONAL') }}
          </span>
        </span>
        <div
          v-if="config.attachment"
          class="flex items-center gap-2 px-3 h-10 rounded-lg bg-n-alpha-2 border border-n-weak"
        >
          <fluent-icon
            icon="document"
            size="16"
            class="text-n-slate-11 shrink-0"
          />
          <span class="flex-1 text-xs text-n-slate-12 truncate">{{
            config.attachment_name
          }}</span>
          <Button
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-x"
            @click="clearMedia"
          />
        </div>
        <label
          v-else
          class="flex items-center justify-center gap-2 h-10 rounded-lg border border-dashed border-n-weak text-xs text-n-slate-11 cursor-pointer hover:border-n-teal-7 hover:text-n-teal-11 transition-colors"
        >
          <fluent-icon v-if="!isUploading" icon="attach" size="16" />
          <span>{{
            isUploading
              ? t('CHATFLOW.EDITOR.UPLOADING')
              : t('CHATFLOW.EDITOR.UPLOAD')
          }}</span>
          <input
            type="file"
            class="hidden"
            :accept="
              kind === 'send_audio'
                ? 'audio/*'
                : 'image/*,video/*,application/pdf'
            "
            @change="uploadMedia"
          />
        </label>
      </div>

      <!-- SAC menu options -->
      <div v-if="isMenu" class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.OPTIONS')
          }}</span>
          <Button
            variant="ghost"
            color="teal"
            size="sm"
            icon="i-lucide-plus"
            :label="t('CHATFLOW.EDITOR.ADD_OPTION')"
            @click="addOption"
          />
        </div>
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.EDITOR.OPTIONS_HINT') }}
        </p>
        <div
          v-for="(opt, index) in options"
          :key="opt.value"
          class="flex items-center gap-2"
        >
          <span
            class="flex items-center justify-center size-7 rounded-md bg-n-amber-3 text-[11px] font-bold text-n-amber-11 shrink-0"
          >
            {{ index + 1 }}
          </span>
          <input
            v-model="opt.label"
            type="text"
            :placeholder="t('CHATFLOW.EDITOR.OPTION_PLACEHOLDER')"
            class="flex-1 h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
          <Button
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-trash-2"
            @click="removeOption(index)"
          />
        </div>
      </div>

      <!-- Set label -->
      <div v-if="kind === 'set_label'" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">{{
          t('CHATFLOW.EDITOR.LABELS')
        }}</span>
        <button
          v-for="label in labels"
          :key="label.id"
          type="button"
          class="flex items-center gap-2 px-3 h-9 rounded-lg border text-sm cursor-pointer transition-colors"
          :class="
            labelIds.includes(label.id)
              ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-12'
              : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
          "
          @click="toggleLabel(label.id)"
        >
          <span
            class="size-2.5 rounded-full"
            :style="{ backgroundColor: label.color }"
          />
          <span class="truncate">{{ label.title }}</span>
        </button>
      </div>

      <!-- Assign agent / team -->
      <div v-if="kind === 'assign_agent'" class="flex flex-col gap-3">
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.AGENT')
          }}</span>
          <select
            v-model="config.agent_id"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option :value="undefined">
              {{ t('CHATFLOW.EDITOR.AGENT_NONE') }}
            </option>
            <option v-for="a in agents" :key="a.id" :value="a.id">
              {{ a.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.TEAM')
          }}</span>
          <select
            v-model="config.team_id"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option :value="undefined">
              {{ t('CHATFLOW.EDITOR.TEAM_NONE') }}
            </option>
            <option v-for="tm in teams" :key="tm.id" :value="tm.id">
              {{ tm.name }}
            </option>
          </select>
        </label>
      </div>

      <!-- Add to Kanban -->
      <div v-if="kind === 'add_to_kanban'" class="flex flex-col gap-3">
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.FUNNEL')
          }}</span>
          <select
            v-model="config.funnel_id"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
            @change="onFunnelChange"
          >
            <option :value="undefined">
              {{ t('CHATFLOW.EDITOR.SELECT') }}
            </option>
            <option v-for="f in funnels" :key="f.id" :value="f.id">
              {{ f.name }}
            </option>
          </select>
        </label>
        <label v-if="funnelStages.length" class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.STAGE')
          }}</span>
          <select
            v-model="config.funnel_stage_id"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option :value="undefined">
              {{ t('CHATFLOW.EDITOR.SELECT') }}
            </option>
            <option v-for="s in funnelStages" :key="s.id" :value="s.id">
              {{ s.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.CARD_TITLE')
          }}</span>
          <input
            v-model="config.title"
            type="text"
            :placeholder="t('CHATFLOW.EDITOR.CARD_TITLE_PLACEHOLDER')"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
        </label>
      </div>

      <!-- Webhook -->
      <div v-if="kind === 'webhook'" class="flex flex-col gap-3">
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.WEBHOOK_URL')
          }}</span>
          <input
            v-model="config.url"
            type="url"
            :placeholder="t('CHATFLOW.EDITOR.WEBHOOK_URL_PLACEHOLDER')"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
          />
        </label>
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('CHATFLOW.EDITOR.WEBHOOK_METHOD')
          }}</span>
          <select
            v-model="config.method"
            class="h-9 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option v-for="m in HTTP_METHODS" :key="m.value" :value="m.value">
              {{ m.label }}
            </option>
          </select>
        </label>
        <p class="text-[11px] text-n-slate-10 m-0">
          {{ t('CHATFLOW.EDITOR.WEBHOOK_HINT') }}
        </p>
      </div>

      <!-- End flow + optional actions -->
      <div v-if="kind === 'end_flow'" class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-11 m-0">
          {{ t('CHATFLOW.EDITOR.END_HINT') }}
        </p>
        <label
          class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
        >
          <input
            v-model="resolveOnEnd"
            type="checkbox"
            class="accent-n-teal-9"
          />
          {{ t('CHATFLOW.EDITOR.END_RESOLVE') }}
        </label>
      </div>
    </div>

    <footer class="flex flex-col gap-2 px-4 py-3 border-t border-n-weak">
      <label
        class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer"
      >
        <input
          type="checkbox"
          :checked="isStart"
          class="accent-n-teal-9"
          @change="emit('setStart')"
        />
        {{ t('CHATFLOW.EDITOR.SET_START') }}
      </label>
      <div class="flex items-center gap-2">
        <Button
          class="flex-1"
          :label="t('CHATFLOW.EDITOR.SAVE')"
          :is-loading="isSaving"
          @click="save"
        />
        <Button
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          @click="emit('remove')"
        />
      </div>
    </footer>
  </aside>
</template>
