<script setup>
/**
 * Recorte quadrado da foto de perfil antes de enviar.
 *
 * O WhatsApp mostra a foto em círculo e corta o que sobra do jeito dele. Aqui
 * o operador arrasta e dá zoom vendo o círculo por cima, e o arquivo que sai já
 * é o quadrado escolhido, então o que aparece no celular do cliente é o que
 * foi visto na tela.
 *
 * Tudo é desenhado num <canvas>, e não com transform em CSS, para seguir a
 * regra de não ter estilo inline nesta base.
 */
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { cropToSquareFile, squareCrop } from '../helpers';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm']);

const { t } = useI18n();

const PREVIEW_SIZE = 320;

const dialogRef = ref(null);
const canvasRef = ref(null);
const image = ref(null);
const fileName = ref('');
const zoom = ref(1);
const offset = ref({ x: 0, y: 0 });
const dragStart = ref(null);
const cropError = ref('');

const label = key => t(`WHATSAPP_PROFILE.CROPPER.${key}`);

const crop = computed(() =>
  image.value
    ? squareCrop(
        { width: image.value.naturalWidth, height: image.value.naturalHeight },
        zoom.value,
        offset.value
      )
    : null
);

const draw = () => {
  const context = canvasRef.value?.getContext?.('2d');
  if (!context || !image.value || !crop.value) return;
  const { x, y, size } = crop.value;
  context.clearRect(0, 0, PREVIEW_SIZE, PREVIEW_SIZE);
  context.drawImage(
    image.value,
    x,
    y,
    size,
    size,
    0,
    0,
    PREVIEW_SIZE,
    PREVIEW_SIZE
  );
};

watch(crop, draw);

const clamp = value => Math.max(-1, Math.min(1, value));

const onPointerDown = event => {
  dragStart.value = {
    x: event.clientX,
    y: event.clientY,
    offset: { ...offset.value },
  };
  event.target.setPointerCapture?.(event.pointerId);
};

// Arrastar a imagem para a direita mostra mais do lado esquerdo dela, por
// isso o sinal invertido. A folga é medida em pixels da prévia.
const onPointerMove = event => {
  if (!dragStart.value || !image.value) return;
  const { naturalWidth: width, naturalHeight: height } = image.value;
  const size = Math.min(width, height) / zoom.value;
  const scale = size / PREVIEW_SIZE;
  const slackX = (width - size) / 2 || 1;
  const slackY = (height - size) / 2 || 1;
  offset.value = {
    x: clamp(
      dragStart.value.offset.x -
        ((event.clientX - dragStart.value.x) * scale) / slackX
    ),
    y: clamp(
      dragStart.value.offset.y -
        ((event.clientY - dragStart.value.y) * scale) / slackY
    ),
  };
};

const onPointerUp = () => {
  dragStart.value = null;
};

const open = file => {
  cropError.value = '';
  zoom.value = 1;
  offset.value = { x: 0, y: 0 };
  fileName.value = file.name.replace(/\.[^.]+$/, '') || 'profile';
  const img = new Image();
  img.onload = async () => {
    image.value = img;
    await nextTick();
    draw();
  };
  img.src = URL.createObjectURL(file);
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const confirm = async () => {
  try {
    const file = await cropToSquareFile(
      image.value,
      crop.value,
      `${fileName.value}.jpg`
    );
    emit('confirm', file);
  } catch {
    cropError.value = label('ERROR');
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="label('TITLE')"
    :description="label('DESCRIPTION')"
    :confirm-button-label="label('CONFIRM')"
    :cancel-button-label="label('CANCEL')"
    :is-loading="props.isSaving"
    :disable-confirm-button="!image"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-4 items-center">
      <div class="overflow-hidden relative rounded-lg size-80 bg-n-alpha-2">
        <canvas
          ref="canvasRef"
          :width="PREVIEW_SIZE"
          :height="PREVIEW_SIZE"
          class="size-80 touch-none cursor-grab active:cursor-grabbing"
          data-testid="cropper-canvas"
          @pointerdown="onPointerDown"
          @pointermove="onPointerMove"
          @pointerup="onPointerUp"
          @pointercancel="onPointerUp"
        />
        <!-- O círculo é o que o WhatsApp mostra; o resto aparece só na foto
          aberta em tela cheia. -->
        <span
          class="absolute inset-0 rounded-full ring-2 pointer-events-none ring-white/90 shadow-[0_0_0_999px_rgba(0,0,0,0.45)]"
        />
      </div>
      <label class="flex gap-3 items-center w-full text-[13px] text-n-slate-11">
        <span class="i-lucide-zoom-out size-4" />
        <input
          v-model.number="zoom"
          type="range"
          min="1"
          max="3"
          step="0.05"
          class="flex-1 accent-n-brand"
          :aria-label="label('ZOOM')"
          data-testid="cropper-zoom"
        />
        <span class="i-lucide-zoom-in size-4" />
      </label>
      <p class="m-0 text-[12px] text-n-slate-11">{{ label('HINT') }}</p>
      <p v-if="cropError" class="m-0 text-[12px] text-n-ruby-11">
        {{ cropError }}
      </p>
    </div>
  </Dialog>
</template>
