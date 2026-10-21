<script setup>
import { useI18n } from 'vue-i18n';

// Contatos que nunca falaram com o salão (vieram de grupo/CSV frio) só
// entram no disparo com esta confirmação, que fica gravada no disparo e se
// apaga sozinha quando o público muda.
defineProps({
  count: { type: Number, default: 0 },
  confirmed: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['change']);

const { t } = useI18n();
</script>

<template>
  <div
    v-if="count > 0"
    class="flex flex-col gap-2.5 p-4 mt-3 rounded-xl border"
    :class="
      confirmed
        ? 'border-n-amber-7 bg-n-amber-2'
        : 'border-n-amber-6 bg-n-amber-3'
    "
    data-testid="cold-contacts"
  >
    <div class="flex gap-2 items-start">
      <span
        class="i-lucide-shield-alert size-4 shrink-0 mt-0.5 text-n-amber-11"
      />
      <div class="flex flex-col gap-1">
        <span class="text-[13px] font-semibold text-n-amber-12">
          {{ t('BROADCAST.COLD.TITLE', { count }, count) }}
        </span>
        <span class="text-xs text-n-amber-11">
          {{
            confirmed ? t('BROADCAST.COLD.INCLUDED') : t('BROADCAST.COLD.BODY')
          }}
        </span>
      </div>
    </div>
    <label
      class="flex gap-2 items-start px-3 py-2 rounded-lg cursor-pointer bg-n-solid-1"
    >
      <input
        type="checkbox"
        class="mt-0.5"
        :checked="confirmed"
        :disabled="disabled"
        data-testid="cold-contacts-confirm"
        @change="emit('change', $event.target.checked)"
      />
      <span class="text-xs font-medium text-n-slate-12">
        {{ t('BROADCAST.COLD.CONFIRM', { count }, count) }}
      </span>
    </label>
  </div>
</template>
