<script setup>
/**
 * What went wrong and who says so.
 *
 * Two columns on purpose, because they are two different kinds of claim. The
 * flags are the machine's opinion of its own reply, and a machine grading
 * itself is not a quality signal. The feedback is somebody on the team having
 * read it, which is the only number on this screen that can contradict the
 * agent.
 *
 * The flags are severity-ordered, which is why they carry a status colour and
 * always a written label beside it: a reply that invented a price and one that
 * merely sounded unsure need different people on different days, and colour
 * alone cannot say which is which.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  flags: { type: Object, default: () => ({}) },
  quality: { type: Object, default: () => ({}) },
  leads: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

// Same order the supervision queue uses, so the row a human should look at
// first is the row at the top here too.
const FLAG_ORDER = [
  'preco_inventado',
  'horario_divergente',
  'cliente_insatisfeito',
  'promessa_solta',
  'sem_fonte',
  'baixa_confianca',
];
const SEVERE = FLAG_ORDER.slice(0, 3);

const decimal = new Intl.NumberFormat('pt-BR');

const flagRows = computed(() => {
  const counts = props.flags || {};
  const peak = Math.max(...Object.values(counts).map(Number), 0);
  return FLAG_ORDER.filter(flag => counts[flag]).map(flag => ({
    flag,
    count: counts[flag],
    width: peak ? Math.max(4, Math.round((counts[flag] / peak) * 100)) : 0,
    severe: SEVERE.includes(flag),
  }));
});

const feedbackRows = computed(() => [
  { key: 'IDEAL', value: props.quality.ideal || 0 },
  { key: 'UP', value: props.quality.up || 0 },
  { key: 'DOWN', value: props.quality.down || 0 },
  { key: 'PENDING', value: props.quality.pending_application || 0 },
]);

const bandRows = computed(() => {
  const bands = props.leads?.by_band || {};
  return [
    { key: 'hot', value: bands.hot || 0 },
    { key: 'warm', value: bands.warm || 0 },
    { key: 'cold', value: bands.cold || 0 },
  ];
});

const bandClass = {
  hot: 'bg-n-ruby-9',
  warm: 'bg-n-amber-9',
  cold: 'bg-n-blue-9',
};
</script>

<template>
  <div class="grid grid-cols-1 gap-5 lg:grid-cols-3">
    <section class="flex flex-col gap-2">
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('ATHENAS_REPORT.FLAGS.TITLE') }}
      </h4>
      <p v-if="!flagRows.length" class="m-0 text-sm text-n-slate-11">
        {{ t('ATHENAS_REPORT.FLAGS.EMPTY') }}
      </p>
      <ul v-else class="flex flex-col gap-2 m-0 list-none">
        <li v-for="row in flagRows" :key="row.flag" class="flex flex-col gap-1">
          <div class="flex gap-3 justify-between items-baseline">
            <span class="text-[13px] text-n-slate-11">
              {{ t(`ATHENAS_REPORT.FLAGS.${row.flag.toUpperCase()}`) }}
            </span>
            <span class="text-[13px] tabular-nums text-n-slate-12">
              {{ decimal.format(row.count) }}
            </span>
          </div>
          <div class="w-full h-1 rounded-full bg-n-alpha-1">
            <div
              class="h-1 rounded-full"
              :class="row.severe ? 'bg-n-ruby-9' : 'bg-n-amber-9'"
              :style="{ width: `${row.width}%` }"
            />
          </div>
        </li>
      </ul>
    </section>

    <section class="flex flex-col gap-2">
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('ATHENAS_REPORT.FEEDBACK.TITLE') }}
      </h4>
      <p v-if="!quality.reviewed" class="m-0 text-sm text-n-slate-11">
        {{ t('ATHENAS_REPORT.FEEDBACK.EMPTY') }}
      </p>
      <ul v-else class="flex flex-col gap-1.5 m-0 list-none">
        <li
          v-for="row in feedbackRows"
          :key="row.key"
          class="flex gap-3 justify-between items-baseline"
        >
          <span class="text-[13px] text-n-slate-11">
            {{ t(`ATHENAS_REPORT.FEEDBACK.${row.key}`) }}
          </span>
          <span class="text-[13px] tabular-nums text-n-slate-12">
            {{ decimal.format(row.value) }}
          </span>
        </li>
      </ul>
    </section>

    <section class="flex flex-col gap-2">
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('ATHENAS_REPORT.LEADS.TITLE') }}
      </h4>
      <p v-if="!leads?.total" class="m-0 text-sm text-n-slate-11">
        {{ t('ATHENAS_REPORT.LEADS.EMPTY') }}
      </p>
      <ul v-else class="flex flex-col gap-1.5 m-0 list-none">
        <li
          v-for="row in bandRows"
          :key="row.key"
          class="flex gap-2 items-baseline"
        >
          <span
            class="flex-shrink-0 w-2 h-2 rounded-full"
            :class="bandClass[row.key]"
          />
          <span class="flex-1 text-[13px] text-n-slate-11">
            {{ t(`ATHENAS_REPORT.LEADS.${row.key.toUpperCase()}`) }}
          </span>
          <span class="text-[13px] tabular-nums text-n-slate-12">
            {{ decimal.format(row.value) }}
          </span>
        </li>
      </ul>
    </section>
  </div>
</template>
