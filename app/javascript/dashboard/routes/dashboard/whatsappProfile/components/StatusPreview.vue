<script setup>
/**
 * Como o status aparece no celular: a tela em pé, com o texto centralizado no
 * fundo colorido ou a mídia com a legenda por baixo. Serve ao compositor, à
 * confirmação e ao histórico, para os três mostrarem a mesma coisa.
 */
import { computed } from 'vue';

import { backgroundClass, fontPreviewClass } from '../helpers';

const props = defineProps({
  kind: { type: String, default: 'text' },
  body: { type: String, default: '' },
  backgroundColor: { type: String, default: '' },
  font: { type: Number, default: 0 },
  mediaUrl: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  compact: { type: Boolean, default: false },
});

const isText = computed(() => props.kind === 'text');
</script>

<template>
  <div
    class="flex overflow-hidden relative flex-col justify-center items-center rounded-xl aspect-[9/16] shrink-0"
    :class="[
      compact ? 'w-14' : 'w-full max-w-56',
      isText ? backgroundClass(backgroundColor) : 'bg-n-slate-12',
    ]"
    data-testid="status-preview"
  >
    <p
      v-if="isText"
      class="m-0 text-center text-white break-words whitespace-pre-line"
      :class="[
        fontPreviewClass(font),
        compact ? 'p-1 text-[6px] line-clamp-6' : 'p-5 text-lg leading-snug',
      ]"
    >
      {{ body || placeholder }}
    </p>
    <template v-else>
      <img
        v-if="kind === 'image' && mediaUrl"
        :src="mediaUrl"
        alt=""
        class="object-contain w-full h-full"
      />
      <video
        v-else-if="kind === 'video' && mediaUrl"
        :src="mediaUrl"
        class="object-contain w-full h-full"
        muted
        playsinline
        :controls="!compact"
      />
      <span
        v-else
        class="text-white/70 size-6"
        :class="kind === 'video' ? 'i-lucide-video' : 'i-lucide-image'"
      />
      <p
        v-if="body && !compact"
        class="absolute inset-x-0 bottom-0 px-3 py-2 m-0 text-[13px] text-center text-white bg-black/50 line-clamp-3"
      >
        {{ body }}
      </p>
    </template>
  </div>
</template>
