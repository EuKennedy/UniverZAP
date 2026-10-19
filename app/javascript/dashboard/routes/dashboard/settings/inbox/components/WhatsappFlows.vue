<script setup>
/**
 * Formulários nativos do WhatsApp (Flows) da caixa.
 *
 * O operador cria a partir de um modelo do vertical (ou cola um Flow JSON),
 * publica e deprecia daqui, sem ir ao Gerenciador da Meta. O envio não é
 * daqui: é a etapa "Enviar formulário" do Chatflow.
 */
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});

const { t } = useI18n();

const CATEGORIES = [
  'APPOINTMENT_BOOKING',
  'SIGN_UP',
  'LEAD_GENERATION',
  'CUSTOMER_SUPPORT',
  'SURVEY',
  'CONTACT_US',
  'OTHER',
];

const flows = ref([]);
const templates = ref([]);
const isLoading = ref(false);
const isSubmitting = ref(false);
const loadError = ref('');
const formError = ref('');
const showAdvanced = ref(false);
const form = ref({ template_key: '', name: '' });
const advanced = ref({ name: '', category: 'OTHER', json: '' });
const editingId = ref(null);
const editingJson = ref('');
const busyId = ref(null);

const canCreate = computed(
  () => Boolean(form.value.template_key) && !isSubmitting.value
);
const canCreateAdvanced = computed(
  () =>
    advanced.value.name.trim() &&
    advanced.value.json.trim() &&
    !isSubmitting.value
);

const errorOf = (error, fallback) =>
  error?.response?.data?.error || t(fallback);

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const [{ data: list }, { data: tpl }] = await Promise.all([
      WhatsappFlowsAPI.list(props.inboxId),
      WhatsappFlowsAPI.templates(),
    ]);
    flows.value = list || [];
    templates.value = tpl.templates || [];
  } catch (error) {
    loadError.value = errorOf(error, 'WHATSAPP_FLOWS.LOAD_FAILED');
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

const create = async payload => {
  isSubmitting.value = true;
  formError.value = '';
  try {
    await WhatsappFlowsAPI.create({ inbox_id: props.inboxId, ...payload });
    useAlert(t('WHATSAPP_FLOWS.CREATED'));
    form.value = { template_key: '', name: '' };
    advanced.value = { name: '', category: 'OTHER', json: '' };
    await load();
  } catch (error) {
    // O erro da Meta chega inteiro: aqui quem lê é quem corrige o JSON.
    formError.value = errorOf(error, 'WHATSAPP_FLOWS.CREATE_FAILED');
    await load();
  } finally {
    isSubmitting.value = false;
  }
};

const createFromTemplate = () =>
  create({
    template_key: form.value.template_key,
    name: form.value.name.trim(),
  });

const parseJson = text => {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
};

const createAdvanced = () => {
  const flowJson = parseJson(advanced.value.json);
  if (!flowJson) {
    formError.value = t('WHATSAPP_FLOWS.INVALID_JSON');
    return;
  }
  create({
    name: advanced.value.name.trim(),
    category: advanced.value.category,
    flow_json: flowJson,
  });
};

const run = async (flow, action, successKey) => {
  busyId.value = flow.id;
  try {
    await action();
    if (successKey) useAlert(t(successKey));
    await load();
  } catch (error) {
    useAlert(errorOf(error, 'WHATSAPP_FLOWS.ACTION_FAILED'));
  } finally {
    busyId.value = null;
  }
};

const publish = flow =>
  run(
    flow,
    () => WhatsappFlowsAPI.publish(flow.id),
    'WHATSAPP_FLOWS.PUBLISHED_OK'
  );
const deprecate = flow =>
  run(
    flow,
    () => WhatsappFlowsAPI.deprecate(flow.id),
    'WHATSAPP_FLOWS.DEPRECATED_OK'
  );
const sync = flow => run(flow, () => WhatsappFlowsAPI.sync(flow.id));
const duplicate = flow =>
  run(flow, () =>
    WhatsappFlowsAPI.create({
      inbox_id: props.inboxId,
      name: `${flow.name} ${t('WHATSAPP_FLOWS.DUPLICATE_SUFFIX')}`,
      category: flow.category,
      flow_json: flow.flow_json,
    })
  );
const remove = flow => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('WHATSAPP_FLOWS.DELETE_CONFIRM'))) return;
  run(flow, () => WhatsappFlowsAPI.remove(flow.id));
};

const startEdit = flow => {
  editingId.value = flow.id;
  editingJson.value = JSON.stringify(flow.flow_json, null, 2);
};
const cancelEdit = () => {
  editingId.value = null;
  editingJson.value = '';
};
const saveEdit = flow => {
  const flowJson = parseJson(editingJson.value);
  if (!flowJson) {
    useAlert(t('WHATSAPP_FLOWS.INVALID_JSON'));
    return;
  }
  run(
    flow,
    async () => {
      await WhatsappFlowsAPI.update(flow.id, { flow_json: flowJson });
      cancelEdit();
    },
    'WHATSAPP_FLOWS.SAVED'
  );
};

const toneFor = status =>
  ({
    published: 'text-n-teal-11 bg-n-alpha-1',
    deprecated: 'text-n-slate-11 bg-n-alpha-1',
    blocked: 'text-n-ruby-11 bg-n-alpha-1',
    throttled: 'text-n-amber-11 bg-n-alpha-1',
  })[status] || 'text-n-amber-11 bg-n-alpha-1';

const statusLabel = status =>
  t(`WHATSAPP_FLOWS.STATUS.${String(status).toUpperCase()}`);
const flowMeta = flow =>
  `${flow.category} · ${flow.meta_flow_id || t('WHATSAPP_FLOWS.NOT_ON_META')}`;
const templateLabel = tpl => `${tpl.name} — ${tpl.description}`;

const inputClass =
  'px-3 h-10 text-sm rounded-lg border outline-none border-n-weak bg-n-alpha-1 text-n-slate-12';
const textareaClass =
  'px-3 py-2 font-mono text-xs rounded-lg border outline-none resize-y border-n-weak bg-n-alpha-1 text-n-slate-12';
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <section class="flex flex-col gap-3 max-w-2xl">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('WHATSAPP_FLOWS.NEW') }}
      </h2>
      <p class="m-0 text-[13px] text-n-slate-11">
        {{ t('WHATSAPP_FLOWS.NEW_HINT') }}
      </p>

      <label class="flex flex-col gap-1 text-[13px] text-n-slate-11">
        {{ t('WHATSAPP_FLOWS.TEMPLATE') }}
        <select v-model="form.template_key" :class="inputClass">
          <option value="">{{ t('WHATSAPP_FLOWS.TEMPLATE_NONE') }}</option>
          <option v-for="tpl in templates" :key="tpl.key" :value="tpl.key">
            {{ templateLabel(tpl) }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-[13px] text-n-slate-11">
        {{ t('WHATSAPP_FLOWS.NAME') }}
        <input
          v-model="form.name"
          :placeholder="t('WHATSAPP_FLOWS.NAME_PLACEHOLDER')"
          :class="inputClass"
        />
      </label>

      <div class="flex gap-3 items-center">
        <Button
          size="sm"
          :label="t('WHATSAPP_FLOWS.CREATE')"
          :is-loading="isSubmitting"
          :disabled="!canCreate"
          @click="createFromTemplate"
        />
        <button
          type="button"
          class="text-[13px] text-n-slate-11 underline cursor-pointer"
          @click="showAdvanced = !showAdvanced"
        >
          {{ t('WHATSAPP_FLOWS.ADVANCED') }}
        </button>
      </div>

      <div v-if="showAdvanced" class="flex flex-col gap-3 pt-2">
        <p class="m-0 text-[13px] text-n-slate-11">
          {{ t('WHATSAPP_FLOWS.ADVANCED_HINT') }}
        </p>
        <div class="flex gap-3">
          <label class="flex flex-col flex-1 gap-1 text-[13px] text-n-slate-11">
            {{ t('WHATSAPP_FLOWS.NAME') }}
            <input v-model="advanced.name" :class="inputClass" />
          </label>
          <label class="flex flex-col flex-1 gap-1 text-[13px] text-n-slate-11">
            {{ t('WHATSAPP_FLOWS.CATEGORY') }}
            <select v-model="advanced.category" :class="inputClass">
              <option v-for="c in CATEGORIES" :key="c" :value="c">
                {{ c }}
              </option>
            </select>
          </label>
        </div>
        <label class="flex flex-col gap-1 text-[13px] text-n-slate-11">
          {{ t('WHATSAPP_FLOWS.JSON') }}
          <textarea v-model="advanced.json" rows="12" :class="textareaClass" />
        </label>
        <div>
          <Button
            size="sm"
            :label="t('WHATSAPP_FLOWS.CREATE')"
            :is-loading="isSubmitting"
            :disabled="!canCreateAdvanced"
            @click="createAdvanced"
          />
        </div>
      </div>

      <p v-if="formError" class="m-0 text-[13px] text-n-ruby-11">
        {{ formError }}
      </p>
    </section>

    <section class="flex flex-col gap-2">
      <div class="flex gap-2 justify-between items-center">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('WHATSAPP_FLOWS.LIST') }}
        </h2>
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-refresh-cw"
          :is-loading="isLoading"
          @click="load"
        />
      </div>
      <p class="m-0 text-[12px] text-n-slate-10">
        {{ t('WHATSAPP_FLOWS.SEND_HINT') }}
      </p>

      <p v-if="loadError" class="m-0 text-[13px] text-n-ruby-11">
        {{ loadError }}
      </p>
      <p
        v-else-if="!isLoading && !flows.length"
        class="m-0 text-[13px] text-n-slate-11"
      >
        {{ t('WHATSAPP_FLOWS.EMPTY') }}
      </p>

      <div
        v-for="flow in flows"
        :key="flow.id"
        class="flex flex-col gap-2 p-3 rounded-lg border border-n-weak"
      >
        <div class="flex gap-3 items-center">
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-sm truncate text-n-slate-12">{{
              flow.name
            }}</span>
            <span class="text-[12px] text-n-slate-11">
              {{ flowMeta(flow) }}
            </span>
            <span
              v-if="flow.validation_errors?.length"
              class="text-[12px] text-n-ruby-11"
            >
              {{
                t('WHATSAPP_FLOWS.VALIDATION_ERRORS', {
                  count: flow.validation_errors.length,
                })
              }}
            </span>
          </div>
          <span
            class="px-2 py-0.5 text-[11px] rounded-full flex-shrink-0"
            :class="toneFor(flow.status)"
          >
            {{ statusLabel(flow.status) }}
          </span>
        </div>

        <ul
          v-if="flow.validation_errors?.length"
          class="m-0 pl-4 text-[12px] text-n-ruby-11 list-disc"
        >
          <li v-for="(err, index) in flow.validation_errors" :key="index">
            {{ err.message || err.error || JSON.stringify(err) }}
          </li>
        </ul>

        <div class="flex flex-wrap gap-2 items-center">
          <Button
            v-if="flow.status === 'draft' && flow.meta_flow_id"
            size="xs"
            :label="t('WHATSAPP_FLOWS.PUBLISH')"
            :is-loading="busyId === flow.id"
            :disabled="flow.validation_errors?.length > 0"
            @click="publish(flow)"
          />
          <Button
            v-if="['published', 'throttled', 'blocked'].includes(flow.status)"
            size="xs"
            variant="ghost"
            :label="t('WHATSAPP_FLOWS.DEPRECATE')"
            :is-loading="busyId === flow.id"
            @click="deprecate(flow)"
          />
          <Button
            v-if="flow.meta_flow_id"
            size="xs"
            variant="ghost"
            icon="i-lucide-refresh-cw"
            :label="t('WHATSAPP_FLOWS.SYNC')"
            :is-loading="busyId === flow.id"
            @click="sync(flow)"
          />
          <a
            v-if="flow.preview_url"
            :href="flow.preview_url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-[13px] text-n-teal-11 underline"
          >
            {{ t('WHATSAPP_FLOWS.PREVIEW') }}
          </a>
          <span
            v-else-if="flow.meta_flow_id"
            class="text-[12px] text-n-slate-10"
          >
            {{ t('WHATSAPP_FLOWS.PREVIEW_HINT') }}
          </span>
          <Button
            v-if="flow.status === 'draft' && editingId !== flow.id"
            size="xs"
            variant="ghost"
            icon="i-lucide-code"
            :label="t('WHATSAPP_FLOWS.EDIT_JSON')"
            @click="startEdit(flow)"
          />
          <Button
            size="xs"
            variant="ghost"
            icon="i-lucide-copy"
            :label="t('WHATSAPP_FLOWS.DUPLICATE')"
            :is-loading="busyId === flow.id"
            @click="duplicate(flow)"
          />
          <Button
            v-if="flow.status === 'draft'"
            size="xs"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            @click="remove(flow)"
          />
        </div>

        <div v-if="editingId === flow.id" class="flex flex-col gap-2">
          <textarea v-model="editingJson" rows="16" :class="textareaClass" />
          <div class="flex gap-2">
            <Button
              size="xs"
              :label="t('WHATSAPP_FLOWS.SAVE_JSON')"
              :is-loading="busyId === flow.id"
              @click="saveEdit(flow)"
            />
            <Button
              size="xs"
              variant="ghost"
              :label="t('WHATSAPP_FLOWS.CANCEL')"
              @click="cancelEdit"
            />
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
