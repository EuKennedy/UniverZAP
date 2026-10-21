<script setup>
/**
 * Um passo do fluxo da campanha: o conteúdo (como no compositor), o dia do
 * ciclo, o horário e a repostagem. A mídia sobe na hora em que é escolhida,
 * para o passo já sair do diálogo com o arquivo pronto.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { uploadFile } from 'dashboard/helper/uploadHelper';
import {
  apiErrorMessage,
  MAX_REPOSTS,
  REPOST_INTERVALS,
  renderVariables,
  STATUS_BACKGROUNDS,
  STATUS_FONTS,
  STATUS_TEXT_LIMIT,
  STATUS_VARIABLES,
} from '../helpers';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import StatusPreview from './StatusPreview.vue';

const props = defineProps({
  previewName: { type: String, default: '' },
  accountName: { type: String, default: '' },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.CAMPAIGNS.STEP.${key}`);

const KINDS = ['text', 'image', 'video'];

const emptyStep = () => ({
  kind: 'text',
  body: '',
  backgroundColor: STATUS_BACKGROUNDS[0].value,
  font: 0,
  dayOffset: 0,
  timeOfDay: '09:00',
  repostCount: 0,
  repostIntervalHours: 24,
  mediaUrl: '',
  blobId: undefined,
});

const dialogRef = ref(null);
const step = ref(emptyStep());
const index = ref(null);
const isUploading = ref(false);
const formError = ref('');
const fileInput = ref(null);

const isText = computed(() => step.value.kind === 'text');
const repostOptions = computed(() =>
  Array.from({ length: MAX_REPOSTS + 1 }, (_, count) => ({
    value: count,
    label: count
      ? t('WHATSAPP_PROFILE.CAMPAIGNS.STEP.REPOST_TIMES', { count }, count)
      : label('NO_REPOST'),
  }))
);
const intervalOptions = computed(() =>
  REPOST_INTERVALS.map(hours => ({
    value: hours,
    label: t('WHATSAPP_PROFILE.CAMPAIGNS.STEP.EVERY_HOURS', { hours }),
  }))
);
const previewBody = computed(() =>
  renderVariables(step.value.body, {
    conexao: props.previewName,
    empresa: props.accountName,
  })
);

const open = (existing = null, position = null) => {
  step.value = existing ? { ...emptyStep(), ...existing } : emptyStep();
  index.value = position;
  formError.value = '';
  dialogRef.value?.open();
};

const selectKind = kind => {
  step.value = { ...step.value, kind, mediaUrl: '', blobId: undefined };
};

const variableToken = key => `{{${key}}}`;
const insertVariable = key => {
  const body = step.value.body || '';
  const separator = body && !/\s$/.test(body) ? ' ' : '';
  step.value.body = `${body}${separator}${variableToken(key)}`;
};

const handleFile = async () => {
  const file = fileInput.value?.files?.[0];
  if (!file) return;
  isUploading.value = true;
  formError.value = '';
  try {
    const { blobId } = await uploadFile(file);
    step.value = {
      ...step.value,
      blobId,
      mediaUrl: window.URL?.createObjectURL ? URL.createObjectURL(file) : '',
    };
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.UPLOAD')
    );
  } finally {
    isUploading.value = false;
    if (fileInput.value) fileInput.value.value = null;
  }
};

const save = () => {
  if (isText.value && !step.value.body.trim()) {
    formError.value = t('WHATSAPP_PROFILE.ERRORS.TEXT_REQUIRED');
    return;
  }
  if (!isText.value && !step.value.mediaUrl) {
    formError.value = t('WHATSAPP_PROFILE.ERRORS.FILE_REQUIRED');
    return;
  }
  emit('save', { ...step.value, body: step.value.body.trim() }, index.value);
  dialogRef.value?.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="index === null ? label('NEW_TITLE') : label('EDIT_TITLE')"
    :confirm-button-label="label('SAVE')"
    :cancel-button-label="t('WHATSAPP_PROFILE.STATUS.CONFIRM.CANCEL')"
    :is-loading="isUploading"
    type="edit"
    @confirm="save"
  >
    <div class="grid gap-6 items-start md:grid-cols-[minmax(0,1fr)_12rem]">
      <div class="flex flex-col gap-4 min-w-0">
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <label class="flex flex-col gap-1 text-[12px] text-n-slate-11">
            {{ label('DAY') }}
            <input
              v-model.number="step.dayOffset"
              type="number"
              min="0"
              max="365"
              class="!mb-0 !h-9 !px-3 text-sm rounded-lg border-0 outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
              data-testid="step-day"
            />
          </label>
          <label class="flex flex-col gap-1 text-[12px] text-n-slate-11">
            {{ label('TIME') }}
            <input
              v-model="step.timeOfDay"
              type="time"
              class="!mb-0 !h-9 !px-3 text-sm rounded-lg border-0 outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
              data-testid="step-time"
            />
          </label>
          <div class="flex flex-col gap-1 text-[12px] text-n-slate-11">
            {{ label('REPOST') }}
            <Select
              v-model="step.repostCount"
              :options="repostOptions"
              data-testid="step-repost"
            />
          </div>
          <div
            v-if="step.repostCount > 0"
            class="flex flex-col gap-1 text-[12px] text-n-slate-11"
          >
            {{ label('INTERVAL') }}
            <Select
              v-model="step.repostIntervalHours"
              :options="intervalOptions"
              data-testid="step-interval"
            />
          </div>
        </div>
        <p class="-mt-2 m-0 text-[11px] text-n-slate-10">
          {{ label('DAY_HINT') }}
        </p>

        <div class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1">
          <button
            v-for="option in KINDS"
            :key="option"
            type="button"
            class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
            :class="
              step.kind === option
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`step-kind-${option}`"
            @click="selectKind(option)"
          >
            {{ t(`WHATSAPP_PROFILE.STATUS.KIND.${option.toUpperCase()}`) }}
          </button>
        </div>

        <div v-if="!isText" class="flex gap-3 items-center">
          <label
            class="flex gap-2 items-center px-3 h-8 text-[13px] rounded-lg cursor-pointer bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
          >
            <span
              class="size-4"
              :class="
                step.kind === 'image' ? 'i-lucide-image' : 'i-lucide-video'
              "
            />
            {{
              step.kind === 'image'
                ? t('WHATSAPP_PROFILE.STATUS.CHOOSE_IMAGE')
                : t('WHATSAPP_PROFILE.STATUS.CHOOSE_VIDEO')
            }}
            <input
              ref="fileInput"
              type="file"
              class="hidden"
              :accept="
                step.kind === 'image'
                  ? 'image/jpeg,image/png,image/webp'
                  : 'video/*'
              "
              data-testid="step-file"
              @change="handleFile"
            />
          </label>
          <span v-if="isUploading" class="text-[12px] text-n-slate-11">
            {{ label('UPLOADING') }}
          </span>
        </div>

        <TextArea
          v-model="step.body"
          :label="isText ? '' : t('WHATSAPP_PROFILE.STATUS.CAPTION')"
          :placeholder="t('WHATSAPP_PROFILE.STATUS.TEXT_PLACEHOLDER')"
          :max-length="STATUS_TEXT_LIMIT"
          show-character-count
          auto-height
          min-height="5rem"
          data-testid="step-body"
        />
        <div class="flex flex-wrap gap-1.5 items-center -mt-2">
          <span class="text-[11px] text-n-slate-11">
            {{ t('WHATSAPP_PROFILE.STATUS.VARIABLES.LABEL') }}
          </span>
          <button
            v-for="key in STATUS_VARIABLES"
            :key="key"
            type="button"
            class="px-2 py-0.5 font-mono text-[11px] rounded-md border border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
            @click="insertVariable(key)"
          >
            {{ variableToken(key) }}
          </button>
        </div>

        <div v-if="step.kind !== 'image'" class="flex flex-wrap gap-2">
          <button
            v-for="color in STATUS_BACKGROUNDS"
            :key="color.value"
            type="button"
            class="rounded-full transition-transform size-7 hover:scale-110"
            :class="[
              color.className,
              step.backgroundColor === color.value
                ? 'ring-2 ring-offset-2 ring-n-slate-12 ring-offset-n-solid-1'
                : '',
            ]"
            :aria-label="color.value"
            @click="step.backgroundColor = color.value"
          />
        </div>
        <div v-if="isText" class="flex flex-wrap gap-2">
          <button
            v-for="option in STATUS_FONTS"
            :key="option.value"
            type="button"
            class="px-3 py-1.5 text-[13px] rounded-lg border border-n-weak text-n-slate-12"
            :class="[
              option.previewClass,
              step.font === option.value ? 'bg-n-alpha-2 border-n-slate-9' : '',
            ]"
            @click="step.font = option.value"
          >
            {{ t(`WHATSAPP_PROFILE.STATUS.FONTS.${option.key}`) }}
          </button>
        </div>

        <p
          v-if="formError"
          class="m-0 text-[13px] text-n-ruby-11"
          data-testid="step-error"
        >
          {{ formError }}
        </p>
      </div>

      <StatusPreview
        phone
        class="mx-auto"
        :title="previewName"
        :kind="step.kind"
        :body="previewBody"
        :background-color="step.backgroundColor"
        :font="step.font"
        :media-url="step.mediaUrl"
        :placeholder="t('WHATSAPP_PROFILE.STATUS.TEXT_PLACEHOLDER')"
      />
    </div>
  </Dialog>
</template>
