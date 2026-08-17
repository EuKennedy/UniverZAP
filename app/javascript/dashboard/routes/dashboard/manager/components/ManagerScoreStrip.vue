<script setup>
/**
 * As três notas do Gerente: confiabilidade, conversão e custo.
 *
 * Nunca viram uma só. Um índice único esconderia qual metade se mexeu, e a
 * metade que se mexeu é a única informação aqui: um agente que ficou barato
 * porque parou de responder sobe o número único enquanto perde cliente.
 *
 * A quebra por agente só aparece com mais de um agente na conta. Com um
 * agente, a linha repetiria os mesmos três números logo abaixo deles.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { buildScores, SCORE_KEYS } from '../managerFormat';

const props = defineProps({
  scores: { type: Object, default: () => ({}) },
  agents: { type: Array, default: () => [] },
});

const { t } = useI18n();

const label = key => t(`AI_MANAGER.SCORES.${key}`);

const tiles = computed(() => buildScores(props.scores));

const hasBreakdown = computed(() => props.agents.length > 1);

const agentRows = computed(() =>
  props.agents.map(agent => ({
    id: agent.id,
    name: agent.name,
    tiles: buildScores(agent.scores),
  }))
);
</script>

<template>
  <section class="flex flex-col gap-3" data-testid="score-strip">
    <div class="grid gap-3 sm:grid-cols-3">
      <div
        v-for="tile in tiles"
        :key="tile.key"
        class="flex flex-col gap-1 px-4 py-3.5 rounded-xl border border-n-weak bg-n-solid-1"
        :data-testid="`score-${tile.key}`"
      >
        <span
          class="text-[11px] font-medium tracking-wider uppercase text-n-slate-11"
        >
          {{ label(`${tile.key.toUpperCase()}.TITLE`) }}
        </span>
        <div class="flex flex-wrap gap-x-2 gap-y-0.5 items-baseline">
          <span class="text-2xl font-medium tracking-tight text-n-slate-12">
            {{ tile.value }}
          </span>
          <!-- A seta antes do número, porque a direção é o que se lê de
            relance e a porcentagem é o detalhe que vem depois. -->
          <span
            v-if="tile.trend"
            class="flex gap-1 items-center text-[12px] font-medium tabular-nums"
            :class="tile.trend.tone"
            :title="label('COMPARISON')"
            :data-testid="`trend-${tile.key}`"
          >
            <span aria-hidden="true">{{ tile.trend.arrow }}</span>
            {{ tile.trend.label }}
          </span>
        </div>
        <span class="text-[12px] leading-snug text-n-slate-11">
          {{ label(`${tile.key.toUpperCase()}.HINT`) }}
        </span>
      </div>
    </div>

    <!-- Uma tabela e não três chips por linha: com os números alinhados na
      mesma coluna dá para varrer de cima a baixo e ver qual agente está fora
      da curva, que é a única pergunta que uma conta com vários agentes faz. -->
    <div
      v-if="hasBreakdown"
      class="overflow-x-auto rounded-xl border border-n-weak"
      data-testid="agent-breakdown"
    >
      <div class="min-w-[28rem] divide-y divide-n-weak">
        <div
          class="grid gap-4 items-center px-4 py-2 grid-cols-[minmax(0,1fr)_repeat(3,minmax(0,6rem))]"
        >
          <span />
          <span
            v-for="key in SCORE_KEYS"
            :key="key"
            class="text-[11px] font-medium tracking-wider text-right uppercase text-n-slate-11"
          >
            {{ label(`${key.toUpperCase()}.TITLE`) }}
          </span>
        </div>
        <div
          v-for="agent in agentRows"
          :key="agent.id"
          class="grid gap-4 items-center px-4 py-2.5 grid-cols-[minmax(0,1fr)_repeat(3,minmax(0,6rem))]"
        >
          <span class="text-[13px] font-medium truncate text-n-slate-12">
            {{ agent.name }}
          </span>
          <span
            v-for="tile in agent.tiles"
            :key="tile.key"
            class="flex gap-1.5 justify-end items-baseline text-[12px] tabular-nums"
          >
            <span class="font-medium text-n-slate-12">{{ tile.value }}</span>
            <span v-if="tile.trend" :class="tile.trend.tone" aria-hidden="true">
              {{ tile.trend.arrow }}
            </span>
          </span>
        </div>
      </div>
    </div>
  </section>
</template>
