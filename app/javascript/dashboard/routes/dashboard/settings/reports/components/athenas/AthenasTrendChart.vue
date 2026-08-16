<script setup>
/**
 * Uma medida ao longo do tempo, desenhada pelo Chart.js.
 *
 * Substitui as barras que eu tinha feito à mão. O ganho não é estético: com o
 * Chart.js vem eixo com escala real, tooltip que segue o cursor pelo gráfico
 * inteiro em vez de exigir mira na barra, animação na troca de período e
 * redesenho no resize. Tudo isso é UX que dá para escrever à mão e é UX que
 * ninguém deveria escrever à mão.
 *
 * Deliberadamente uma medida só, nunca duas escalas no mesmo plano: alinhar
 * respostas com reais inventa uma correlação que os números nunca afirmaram, e
 * é o erro mais comum de painel. Duas medidas viram dois gráficos.
 */
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';

const props = defineProps({
  title: { type: String, required: true },
  // [{ label, value, display }]
  points: { type: Array, default: () => [] },
  // Um passo da rampa do design system, em hex, porque o canvas não lê classe.
  color: { type: String, default: '#3b82f6' },
  valueHeader: { type: String, default: '' },
  axisHeader: { type: String, default: '' },
});

ChartJS.register(
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale
);

const { t } = useI18n();
const showTable = ref(false);
const ink = ref('#8b9a92');

// O canvas não enxerga variável CSS, então os tokens do tema são lidos do DOM
// uma vez na montagem. Sem isso o gráfico ficaria com cinza fixo e brigaria
// com o tema claro.
onMounted(() => {
  const style = getComputedStyle(document.documentElement);
  ink.value = style.getPropertyValue('--n-slate-11')?.trim() || ink.value;
});

const isEmpty = computed(() => !props.points.some(point => point.value > 0));

const collection = computed(() => ({
  labels: props.points.map(point => point.label),
  datasets: [
    {
      data: props.points.map(point => point.value),
      borderColor: props.color,
      borderWidth: 2,
      // O preenchimento sob a linha é o que faz um período silencioso parecer
      // silencioso em vez de parecer um erro de renderização.
      fill: true,
      backgroundColor: context => {
        const { ctx, chartArea } = context.chart;
        if (!chartArea) return 'transparent';
        const gradient = ctx.createLinearGradient(
          0,
          chartArea.top,
          0,
          chartArea.bottom
        );
        gradient.addColorStop(0, `${props.color}38`);
        gradient.addColorStop(1, `${props.color}00`);
        return gradient;
      },
      tension: 0.35,
      pointRadius: 0,
      pointHoverRadius: 5,
      pointHoverBackgroundColor: props.color,
      pointHoverBorderColor: '#fff',
      pointHoverBorderWidth: 2,
    },
  ],
}));

const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 420 },
  // O cursor não precisa acertar o ponto: em qualquer lugar da coluna o
  // gráfico responde. Um alvo de 4px é um alvo que ninguém acerta.
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(9, 15, 12, .92)',
      padding: 10,
      cornerRadius: 8,
      displayColors: false,
      titleFont: { size: 12, weight: '600' },
      bodyFont: { size: 12 },
      callbacks: {
        label: item =>
          props.points[item.dataIndex]?.display ?? item.formattedValue,
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      border: { display: false },
      ticks: {
        color: ink.value,
        font: { size: 11 },
        maxRotation: 0,
        autoSkipPadding: 24,
      },
    },
    y: {
      beginAtZero: true,
      grid: { color: 'rgba(127,127,127,.12)', drawTicks: false },
      border: { display: false },
      ticks: {
        color: ink.value,
        font: { size: 11 },
        maxTicksLimit: 4,
        padding: 8,
      },
    },
  },
}));
</script>

<template>
  <figure class="flex flex-col gap-3 m-0">
    <figcaption class="flex gap-3 justify-between items-baseline">
      <h4 class="m-0 text-sm font-medium text-n-slate-12">{{ title }}</h4>
      <button
        type="button"
        class="text-xs rounded text-n-slate-11 hover:text-n-slate-12"
        @click="showTable = !showTable"
      >
        {{
          showTable
            ? t('ATHENAS_REPORT.CHART.SHOW_CHART')
            : t('ATHENAS_REPORT.CHART.SHOW_TABLE')
        }}
      </button>
    </figcaption>

    <p
      v-if="isEmpty"
      class="flex items-center m-0 h-40 text-sm text-n-slate-11"
    >
      {{ t('ATHENAS_REPORT.CHART.EMPTY') }}
    </p>

    <!-- A tabela não é plano B, é o mesmo dado alcançável sem cor e sem
      ponteiro. Valor que só existe no hover é valor que parte das pessoas
      simplesmente não lê. -->
    <div v-else-if="showTable" class="overflow-y-auto max-h-64">
      <table class="w-full text-sm border-collapse">
        <thead>
          <tr class="text-left text-n-slate-11">
            <th class="py-1 pr-3 font-medium">{{ axisHeader }}</th>
            <th class="py-1 font-medium text-right">{{ valueHeader }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="point in points"
            :key="point.label"
            class="border-t border-n-weak"
          >
            <td class="py-1 pr-3 text-n-slate-11">{{ point.label }}</td>
            <td class="py-1 text-right tabular-nums text-n-slate-12">
              {{ point.display }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-else class="h-40">
      <Line :data="collection" :options="options" />
    </div>
  </figure>
</template>
