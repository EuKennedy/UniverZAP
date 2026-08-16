<script setup>
/**
 * Publicar status pelo painel.
 *
 * Publicar é irreversível: sai para todos os contatos do número e o painel não
 * tem como apagar depois, porque o endpoint de apagar da WAHA não vale para
 * todos os engines. Por isso o botão nunca publica direto, ele abre a
 * confirmação mostrando exatamente o que vai ao ar.
 */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import WhatsAppProfileAPI from 'dashboard/api/whatsappProfile';
import { apiErrorMessage, STATUS_BACKGROUNDS } from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  inboxId: { type: Number, required: true },
});

const { t } = useI18n();

const KINDS = ['TEXT', 'IMAGE', 'VIDEO'];

const kind = ref('TEXT');
const text = ref('');
const caption = ref('');
const backgroundColor = ref(STATUS_BACKGROUNDS[0]);
const selectedFile = ref(null);
const previewUrl = ref('');
const isPublishing = ref(false);
const publishError = ref('');
const fileInput = ref(null);
const confirmDialogRef = ref(null);

const label = key => t(`WHATSAPP_PROFILE.STATUS.${key}`);
const isText = computed(() => kind.value === 'TEXT');
const isImage = computed(() => kind.value === 'IMAGE');
const isVideo = computed(() => kind.value === 'VIDEO');
const acceptedTypes = computed(() => (isImage.value ? 'image/*' : 'video/*'));

const setFile = file => {
  selectedFile.value = file || null;
  previewUrl.value =
    file && window.URL?.createObjectURL ? URL.createObjectURL(file) : '';
};

const reset = () => {
  text.value = '';
  caption.value = '';
  publishError.value = '';
  setFile(null);
  if (fileInput.value) fileInput.value.value = null;
};

const selectKind = next => {
  kind.value = next;
  reset();
};

const openFileDialog = () => fileInput.value?.click();
const handleFileChange = () => setFile(fileInput.value?.files?.[0]);

// A validação acontece antes da confirmação: pedir "tem certeza?" para algo que
// nem sairia do lugar seria uma pergunta falsa.
const requestPublish = () => {
  publishError.value = '';
  if (isText.value && !text.value.trim()) {
    publishError.value = t('WHATSAPP_PROFILE.ERRORS.TEXT_REQUIRED');
    return;
  }
  if (!isText.value && !selectedFile.value) {
    publishError.value = t('WHATSAPP_PROFILE.ERRORS.FILE_REQUIRED');
    return;
  }
  confirmDialogRef.value?.open();
};

const publishText = () =>
  WhatsAppProfileAPI.publishTextStatus(props.inboxId, {
    text: text.value.trim(),
    backgroundColor: backgroundColor.value,
  });

const publishMedia = async () => {
  const { blobId } = await uploadFile(selectedFile.value);
  if (isImage.value) {
    return WhatsAppProfileAPI.publishImageStatus(props.inboxId, {
      blobId,
      caption: caption.value.trim(),
    });
  }
  return WhatsAppProfileAPI.publishVideoStatus(props.inboxId, {
    blobId,
    backgroundColor: backgroundColor.value,
  });
};

const publish = async () => {
  isPublishing.value = true;
  publishError.value = '';
  try {
    await (isText.value ? publishText() : publishMedia());
    confirmDialogRef.value?.close();
    reset();
    useAlert(label('PUBLISHED'));
  } catch (error) {
    publishError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
    confirmDialogRef.value?.close();
  } finally {
    isPublishing.value = false;
  }
};

watch(() => props.inboxId, reset);
</script>

<template>
  <section
    class="flex flex-col gap-6 p-6 rounded-xl border border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-base font-medium text-n-slate-12">
        {{ label('TITLE') }}
      </h2>
      <!-- As 24 horas ficam aqui, e não escondidas na confirmação: quem decide
        o que publicar precisa saber quanto tempo aquilo dura antes de escrever. -->
      <p class="m-0 text-[13px] text-n-slate-11">
        {{ label('DESCRIPTION') }}
      </p>
    </div>

    <div class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1">
      <button
        v-for="option in KINDS"
        :key="option"
        type="button"
        class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
        :class="
          kind === option
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        :data-testid="`kind-${option.toLowerCase()}`"
        @click="selectKind(option)"
      >
        {{ label(`KIND.${option}`) }}
      </button>
    </div>

    <div v-if="isText" class="flex flex-col gap-4">
      <TextArea
        v-model="text"
        :placeholder="label('TEXT_PLACEHOLDER')"
        :max-length="700"
        show-character-count
        auto-height
        min-height="7rem"
      />
      <div class="flex flex-col gap-2">
        <span
          class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
        >
          {{ label('BACKGROUND') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="color in STATUS_BACKGROUNDS"
            :key="color"
            type="button"
            class="rounded-full transition-transform size-7 hover:scale-110"
            :class="
              backgroundColor === color
                ? 'ring-2 ring-offset-2 ring-n-slate-12 ring-offset-n-solid-1'
                : ''
            "
            :style="{ backgroundColor: color }"
            :aria-label="color"
            @click="backgroundColor = color"
          />
        </div>
      </div>
    </div>

    <div v-else class="flex flex-col gap-4">
      <div class="flex gap-4 items-center">
        <img
          v-if="isImage && previewUrl"
          :src="previewUrl"
          alt=""
          class="object-cover w-20 rounded-lg border h-28 border-n-weak"
        />
        <span
          v-else
          class="flex justify-center items-center w-20 rounded-lg border border-dashed h-28 border-n-weak bg-n-alpha-1 text-n-slate-11"
        >
          <span
            :class="isImage ? 'i-lucide-image' : 'i-lucide-video'"
            class="size-5"
          />
        </span>
        <div class="flex flex-col gap-2 items-start">
          <Button
            slate
            faded
            size="sm"
            :label="isImage ? label('CHOOSE_IMAGE') : label('CHOOSE_VIDEO')"
            @click="openFileDialog"
          />
          <span
            v-if="selectedFile"
            class="text-[12px] text-n-slate-11"
            data-testid="selected-file"
          >
            {{ selectedFile.name }}
          </span>
          <Button
            v-if="selectedFile"
            ghost
            slate
            size="xs"
            :label="label('REMOVE_FILE')"
            @click="setFile(null)"
          />
        </div>
        <input
          ref="fileInput"
          type="file"
          :accept="acceptedTypes"
          class="hidden"
          @change="handleFileChange"
        />
      </div>

      <Input
        v-if="isImage"
        v-model="caption"
        :label="label('CAPTION')"
        :placeholder="label('CAPTION_PLACEHOLDER')"
      />

      <p v-if="isVideo" class="m-0 text-[12px] leading-relaxed text-n-slate-11">
        {{ label('VIDEO_HINT') }}
      </p>
    </div>

    <div class="flex gap-3 justify-between items-center">
      <p
        v-if="publishError"
        class="m-0 text-[13px] text-n-ruby-11"
        data-testid="publish-error"
      >
        {{ publishError }}
      </p>
      <span v-else />
      <Button
        :label="label('PUBLISH')"
        icon="i-lucide-send"
        data-testid="publish-button"
        @click="requestPublish"
      />
    </div>

    <Dialog
      ref="confirmDialogRef"
      type="alert"
      width="md"
      :title="label('CONFIRM.TITLE')"
      :description="label('CONFIRM.DESCRIPTION')"
      :confirm-button-label="label('CONFIRM.CONFIRM')"
      :cancel-button-label="label('CONFIRM.CANCEL')"
      :is-loading="isPublishing"
      @confirm="publish"
    >
      <!-- Confirmar sem ver o que vai ao ar é só um clique a mais. O que torna
        a pergunta útil é o conteúdo em si estar aqui. -->
      <div class="flex flex-col gap-2" data-testid="publish-preview">
        <span
          class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
        >
          {{ label('CONFIRM.PREVIEW') }}
        </span>
        <div
          v-if="isText"
          class="flex justify-center items-center p-6 min-h-32 text-sm text-center text-white rounded-lg"
          :style="{ backgroundColor }"
        >
          {{ text }}
        </div>
        <div v-else class="flex gap-3 items-center">
          <img
            v-if="isImage && previewUrl"
            :src="previewUrl"
            alt=""
            class="object-cover w-16 rounded-lg border h-20 border-n-weak"
          />
          <div class="flex flex-col gap-1 min-w-0">
            <span class="text-[13px] truncate text-n-slate-12">
              {{ selectedFile?.name }}
            </span>
            <span v-if="isImage" class="text-[12px] text-n-slate-11">
              {{ caption.trim() || label('CONFIRM.NO_CAPTION') }}
            </span>
          </div>
        </div>
      </div>
    </Dialog>
  </section>
</template>
