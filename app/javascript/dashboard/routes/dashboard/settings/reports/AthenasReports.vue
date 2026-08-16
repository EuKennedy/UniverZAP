<script setup>
/**
 * Relatórios > Agente de IA.
 *
 * Ocupa o lugar que era do Bot. O bot nativo do Chatwoot está desligado nesta
 * instalação faz tempo, então aquela aba media uma coisa que não acontece mais,
 * enquanto o que responde cliente de verdade aqui é o Athenas e não tinha
 * relatório nenhum fora da tela de um agente por vez.
 */
import ReportHeader from './components/ReportHeader.vue';
import AthenasReportContainer from './components/athenas/AthenasReportContainer.vue';
</script>

<template>
  <ReportHeader :header-title="$t('ATHENAS_REPORT.TITLE')" />
  <div class="flex flex-col gap-4 pb-6">
    <AthenasReportContainer />
  </div>
</template>
