<script setup>
/**
 * Quando ainda não dá para concluir nada.
 *
 * Ocupa o lugar das três notas em vez de aparecer ao lado delas. Notas
 * calculadas em cima de doze conversas seriam ruído com aparência de
 * diagnóstico, e o operador tomaria decisão em cima delas do mesmo jeito,
 * porque número na tela parece número medido.
 *
 * O que a tela deve nesse momento é uma conta: quantas conversas faltam para o
 * Gerente ter o que dizer.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatNumber } from 'dashboard/routes/dashboard/settings/reports/components/athenas/summaryFormat';

const props = defineProps({
  analysed: { type: Number, default: 0 },
  needed: { type: Number, default: 0 },
});

const { t } = useI18n();

const remaining = computed(() => Math.max(props.needed - props.analysed, 0));

// Sem needed não há barra: uma barra sem denominador desenha um progresso
// inventado, que é exatamente o gráfico vazio fingindo análise.
const ratio = computed(() => {
  if (!props.needed) return null;
  return Math.min(Math.round((props.analysed / props.needed) * 100), 100);
});
</script>

<template>
  <section
    class="flex flex-col gap-3 px-5 py-4 rounded-xl border border-n-weak bg-n-solid-1"
    data-testid="data-gap"
  >
    <div class="flex gap-2.5 items-start">
      <span
        class="mt-0.5 shrink-0 i-lucide-hourglass size-4 text-n-amber-11"
        aria-hidden="true"
      />
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-[15px] font-medium text-n-slate-12">
          {{ t('AI_MANAGER.GAP.TITLE') }}
        </h2>
        <p class="m-0 max-w-2xl text-[13px] leading-relaxed text-n-slate-11">
          {{
            t('AI_MANAGER.GAP.BODY', {
              analysed: formatNumber(analysed),
              needed: formatNumber(needed),
            })
          }}
        </p>
      </div>
    </div>

    <div v-if="ratio !== null" class="flex flex-col gap-1.5">
      <div
        class="overflow-hidden w-full h-1 rounded-full bg-n-alpha-2"
        role="progressbar"
        :aria-valuenow="analysed"
        :aria-valuemin="0"
        :aria-valuemax="needed"
      >
        <div
          class="h-full rounded-full bg-n-amber-9"
          :style="{ width: `${ratio}%` }"
        />
      </div>
      <span
        class="text-[12px] tabular-nums text-n-slate-11"
        data-testid="data-gap-remaining"
      >
        {{ t('AI_MANAGER.GAP.REMAINING', { n: formatNumber(remaining) }) }}
      </span>
    </div>
  </section>
</template>
