<script setup>
// Create/edit form for one Ai::CustomTool ("Integração"). Kept self-contained
// on purpose: it mirrors Captain's custom-tool form but carries its own
// ATHENAS.* copy and its own field widgets, so the Athenas module never depends
// on the (being-deprecated) Captain UI. Credentials are write-only: on edit the
// backend never returns auth_config, so the auth fields start blank and are
// only sent when the user actually types new ones.
import { reactive, computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
  tool: {
    type: Object,
    default: () => ({}),
  },
  saving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

// The backend slug is "…"-parameterized from the title and fed to the model as
// the function name; cap the title so the slug stays well under the 64-char API
// limit.
const MAX_TITLE = 55;

const state = reactive({
  title: '',
  description: '',
  endpoint_url: '',
  http_method: 'GET',
  auth_type: 'none',
  auth_config: {},
  param_schema: [],
  request_template: '',
  response_template: '',
  enabled: true,
});

const showErrors = ref(false);
const advancedOpen = ref(false);

watch(
  () => props.tool,
  tool => {
    if (props.mode !== 'edit' || !tool || !tool.id) return;
    state.title = tool.title || '';
    state.description = tool.description || '';
    state.endpoint_url = tool.endpoint_url || '';
    state.http_method = tool.http_method || 'GET';
    state.auth_type = tool.auth_type || 'none';
    // auth_config is deliberately never returned by the API. Start blank.
    state.auth_config = {};
    state.param_schema = (tool.param_schema || []).map(param => ({ ...param }));
    state.enabled = tool.enabled ?? true;
  },
  { immediate: true }
);

// Same reset the rest of the app does: a changed auth type must not carry the
// previous type's fields.
watch(
  () => state.auth_type,
  () => {
    state.auth_config = {};
  }
);

const methodOptions = [
  { value: 'GET', label: 'GET' },
  { value: 'POST', label: 'POST' },
];

const authTypeOptions = computed(() => [
  { value: 'none', label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH_TYPES.NONE') },
  {
    value: 'bearer',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH_TYPES.BEARER'),
  },
  {
    value: 'basic',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH_TYPES.BASIC'),
  },
  {
    value: 'api_key',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH_TYPES.API_KEY'),
  },
]);

const paramTypeOptions = computed(() => [
  {
    value: 'string',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAM_TYPES.STRING'),
  },
  {
    value: 'number',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAM_TYPES.NUMBER'),
  },
  {
    value: 'boolean',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAM_TYPES.BOOLEAN'),
  },
  {
    value: 'array',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAM_TYPES.ARRAY'),
  },
  {
    value: 'object',
    label: t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAM_TYPES.OBJECT'),
  },
]);

const titleError = computed(() => {
  if (!showErrors.value) return '';
  if (!state.title.trim())
    return t('ATHENAS.EDIT.INTEGRATIONS.FORM.NAME.ERROR');
  if (state.title.length > MAX_TITLE) {
    return t('ATHENAS.EDIT.INTEGRATIONS.FORM.NAME.MAX_LENGTH_ERROR', {
      max: MAX_TITLE,
    });
  }
  return '';
});

const endpointError = computed(() => {
  if (!showErrors.value) return '';
  if (!state.endpoint_url.trim()) {
    return t('ATHENAS.EDIT.INTEGRATIONS.FORM.ENDPOINT.ERROR');
  }
  return '';
});

const addParam = () => {
  state.param_schema.push({
    name: '',
    type: 'string',
    description: '',
    required: false,
  });
};

const removeParam = index => {
  state.param_schema.splice(index, 1);
};

const buildPayload = () => {
  const payload = {
    title: state.title.trim(),
    description: state.description,
    endpoint_url: state.endpoint_url.trim(),
    http_method: state.http_method,
    auth_type: state.auth_type,
    enabled: state.enabled,
    request_template: state.request_template,
    response_template: state.response_template,
    // Half-filled rows can't be described to the model: drop the nameless ones.
    param_schema: state.param_schema
      .filter(param => param.name && param.name.trim())
      .map(param => ({
        name: param.name.trim(),
        type: param.type || 'string',
        description: param.description || '',
        required: !!param.required,
      })),
  };

  const authFilled = Object.values(state.auth_config || {}).some(
    value =>
      value !== undefined && value !== null && String(value).trim() !== ''
  );
  if (state.auth_type === 'none') {
    payload.auth_config = {};
  } else if (authFilled) {
    payload.auth_config = state.auth_config;
  }
  // On edit with untouched credentials we omit auth_config entirely so the
  // stored one is preserved (it is never sent back to prefill the form).
  return payload;
};

const handleSubmit = () => {
  showErrors.value = true;
  if (titleError.value || endpointError.value) return;
  emit('submit', buildPayload());
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <div class="flex items-center justify-between gap-3">
      <h3 class="text-[15px] font-semibold text-n-slate-12">
        {{
          mode === 'edit'
            ? t('ATHENAS.EDIT.INTEGRATIONS.FORM.EDIT_TITLE')
            : t('ATHENAS.EDIT.INTEGRATIONS.FORM.CREATE_TITLE')
        }}
      </h3>
    </div>

    <Input
      v-model="state.title"
      :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.NAME.LABEL')"
      :placeholder="t('ATHENAS.EDIT.INTEGRATIONS.FORM.NAME.PLACEHOLDER')"
      :message="titleError"
      :message-type="titleError ? 'error' : 'info'"
    />

    <TextArea
      v-model="state.description"
      :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('ATHENAS.EDIT.INTEGRATIONS.FORM.DESCRIPTION.PLACEHOLDER')"
      :rows="2"
    />

    <div class="flex gap-2">
      <div class="flex flex-col gap-1 w-28">
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.METHOD.LABEL') }}
        </label>
        <ComboBox
          v-model="state.http_method"
          :options="methodOptions"
          class="[&>div>button]:bg-n-alpha-black2 [&_li]:font-mono [&_button]:font-mono"
        />
      </div>
      <Input
        v-model="state.endpoint_url"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.ENDPOINT.LABEL')"
        :placeholder="t('ATHENAS.EDIT.INTEGRATIONS.FORM.ENDPOINT.PLACEHOLDER')"
        :message="endpointError"
        :message-type="endpointError ? 'error' : 'info'"
        class="flex-1"
      />
    </div>
    <p class="-mt-2 text-xs text-n-slate-11">
      {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.ENDPOINT.HINT') }}
    </p>

    <div class="flex flex-col gap-1">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH_TYPE.LABEL') }}
      </label>
      <ComboBox
        v-model="state.auth_type"
        :options="authTypeOptions"
        class="[&>div>button]:bg-n-alpha-black2"
      />
    </div>

    <p
      v-if="mode === 'edit' && state.auth_type !== 'none'"
      class="-mt-2 text-xs text-n-amber-11"
    >
      {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.EDIT_HINT') }}
    </p>

    <div class="flex flex-col gap-2">
      <Input
        v-if="state.auth_type === 'bearer'"
        v-model="state.auth_config.token"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.BEARER_TOKEN')"
        :placeholder="
          t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.BEARER_TOKEN_PLACEHOLDER')
        "
      />
      <template v-else-if="state.auth_type === 'basic'">
        <Input
          v-model="state.auth_config.username"
          :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.USERNAME')"
          :placeholder="
            t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.USERNAME_PLACEHOLDER')
          "
        />
        <Input
          v-model="state.auth_config.password"
          type="password"
          :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.PASSWORD')"
          :placeholder="
            t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.PASSWORD_PLACEHOLDER')
          "
        />
      </template>
      <template v-else-if="state.auth_type === 'api_key'">
        <Input
          v-model="state.auth_config.name"
          :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.API_KEY_NAME')"
          :placeholder="
            t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.API_KEY_NAME_PLACEHOLDER')
          "
        />
        <Input
          v-model="state.auth_config.key"
          :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.API_KEY_VALUE')"
          :placeholder="
            t('ATHENAS.EDIT.INTEGRATIONS.FORM.AUTH.API_KEY_VALUE_PLACEHOLDER')
          "
        />
      </template>
    </div>

    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAMS.LABEL') }}
      </label>
      <p class="-mt-1 text-xs text-n-slate-11">
        {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAMS.HELP') }}
      </p>
      <ul v-if="state.param_schema.length" class="grid gap-2 list-none">
        <li
          v-for="(param, index) in state.param_schema"
          :key="index"
          class="flex items-start gap-2 p-3 rounded-lg border border-n-weak bg-n-alpha-2"
        >
          <div class="flex flex-col flex-1 gap-3">
            <div class="grid grid-cols-3 gap-2">
              <Input
                v-model="param.name"
                :placeholder="
                  t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAMS.NAME_PLACEHOLDER')
                "
                class="col-span-2 [&_input]:font-mono"
              />
              <ComboBox
                v-model="param.type"
                :options="paramTypeOptions"
                class="[&>div>button]:bg-n-alpha-black2"
              />
            </div>
            <Input
              v-model="param.description"
              :placeholder="
                t(
                  'ATHENAS.EDIT.INTEGRATIONS.FORM.PARAMS.DESCRIPTION_PLACEHOLDER'
                )
              "
            />
            <label class="flex items-center gap-2 cursor-pointer">
              <Checkbox v-model="param.required" />
              <span class="text-sm text-n-slate-11">
                {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAMS.REQUIRED') }}
              </span>
            </label>
          </div>
          <Button
            variant="faded"
            color="slate"
            icon="i-lucide-trash-2"
            class="flex-shrink-0"
            type="button"
            @click="removeParam(index)"
          />
        </li>
      </ul>
      <Button
        type="button"
        variant="ghost"
        color="blue"
        size="sm"
        icon="i-lucide-plus"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.PARAMS.ADD')"
        @click="addParam"
      />
    </div>

    <button
      type="button"
      class="flex items-center gap-1.5 text-xs font-medium text-n-slate-11 hover:text-n-slate-12 w-fit"
      @click="advancedOpen = !advancedOpen"
    >
      <span
        :class="
          advancedOpen ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'
        "
        class="size-3.5"
      />
      {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.ADVANCED') }}
    </button>

    <template v-if="advancedOpen">
      <TextArea
        v-if="state.http_method === 'POST'"
        v-model="state.request_template"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.REQUEST_TEMPLATE.LABEL')"
        :placeholder="
          t('ATHENAS.EDIT.INTEGRATIONS.FORM.REQUEST_TEMPLATE.PLACEHOLDER')
        "
        :rows="3"
        class="[&_textarea]:font-mono"
      />
      <TextArea
        v-model="state.response_template"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.RESPONSE_TEMPLATE.LABEL')"
        :placeholder="
          t('ATHENAS.EDIT.INTEGRATIONS.FORM.RESPONSE_TEMPLATE.PLACEHOLDER')
        "
        :rows="3"
        class="[&_textarea]:font-mono"
      />
    </template>

    <label class="flex items-center gap-2 cursor-pointer">
      <Checkbox v-model="state.enabled" />
      <span class="text-sm text-n-slate-11">
        {{ t('ATHENAS.EDIT.INTEGRATIONS.FORM.ENABLED.LABEL') }}
      </span>
    </label>

    <div class="flex gap-3 items-center w-full pt-1">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.FORM.CANCEL')"
        class="w-full"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        :label="
          mode === 'edit'
            ? t('ATHENAS.EDIT.INTEGRATIONS.FORM.SAVE')
            : t('ATHENAS.EDIT.INTEGRATIONS.FORM.CREATE')
        "
        class="w-full"
        :is-loading="saving"
        :disabled="saving"
      />
    </div>
  </form>
</template>
