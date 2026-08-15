<script setup>
/**
 * One measure over one ordered axis. Deliberately not configurable into a
 * second series or a second scale.
 *
 * Two y-scales on one plot is the most common way a dashboard invents a
 * correlation that is not in the data: the alignment between the scales is
 * arbitrary, so the reader sees a relationship the numbers never claimed.
 * Replies and spend are different units, so they get two of these instead of
 * one clever chart.
 *
 * One series means one hue and no legend — the title already names what the
 * bars are. Colour carries nothing here that the height does not, which is why
 * a value ramp would be wrong: it would spend the only free channel restating
 * the bar length.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  title: { type: String, required: true },
  // [{ key, label, axisLabel, value, display }]
  points: { type: Array, default: () => [] },
  // A single ramp step from the design system, passed in rather than chosen
  // here so the caller decides what this chart is about.
  barClass: { type: String, default: 'bg-n-blue-9' },
  valueHeader: { type: String, default: '' },
  axisHeader: { type: String, default: '' },
});

const { t } = useI18n();
const showTable = ref(false);
const hovered = ref(null);

const peak = computed(() =>
  props.points.reduce((max, point) => Math.max(max, point.value || 0), 0)
);

const isEmpty = computed(() => peak.value === 0);

// A floor of 2px, so a day with one reply is a visible mark rather than a gap
// the reader mistakes for silence.
const heightFor = point => {
  if (!point.value) return 0;
  return Math.max(2, Math.round((point.value / peak.value) * 100));
};

// Selective, never one label per bar: ninety dates along an axis collide into a
// grey smear. The ends and the middle are what orient a reader; the rest is in
// the tooltip and in the table.
const axisLabels = computed(() => {
  const total = props.points.length;
  if (total === 0) return [];
  const marks = [0, Math.floor((total - 1) / 2), total - 1];
  return [...new Set(marks)].map(index => props.points[index]);
});
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
      class="flex items-center m-0 h-32 text-sm text-n-slate-11"
    >
      {{ t('ATHENAS_REPORT.CHART.EMPTY') }}
    </p>

    <!-- The table is not a fallback, it is the same data reachable without
      colour or a pointer. A value that can only be got at by hovering is a
      value some people simply cannot read. -->
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
            :key="point.key"
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

    <template v-else>
      <div class="flex gap-0.5 items-end h-32">
        <!-- The hit area is the whole column, not the bar: a quiet Tuesday is
          2px tall and nobody can land a pointer on that. -->
        <div
          v-for="point in points"
          :key="point.key"
          class="flex relative flex-1 justify-center items-end h-full min-w-0 group"
          @mouseenter="hovered = point.key"
          @mouseleave="hovered = null"
        >
          <div
            class="w-full rounded-t transition-opacity"
            :class="[
              barClass,
              hovered === point.key ? 'opacity-100' : 'opacity-80',
            ]"
            :style="{ height: `${heightFor(point)}%` }"
          />
          <div
            v-if="hovered === point.key"
            class="absolute bottom-full z-10 px-2 py-1 mb-1 text-xs whitespace-nowrap rounded-md border shadow-lg pointer-events-none border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            {{ point.label }}
            <span class="font-medium tabular-nums">{{ point.display }}</span>
          </div>
        </div>
      </div>
      <div class="flex justify-between text-[11px] text-n-slate-11">
        <span v-for="mark in axisLabels" :key="mark.key">
          {{ mark.axisLabel || mark.label }}
        </span>
      </div>
    </template>
  </figure>
</template>
