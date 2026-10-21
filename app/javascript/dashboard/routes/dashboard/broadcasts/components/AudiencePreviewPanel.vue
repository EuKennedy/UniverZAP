<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// "Quem vai receber" antes de confirmar: quantos saem, quem a guarda segura,
// quanto tempo a cadência leva e o texto exato de uma amostra.
const props = defineProps({
  preview: { type: Object, required: true },
});

const { t } = useI18n();

const excludedEntries = computed(() =>
  Object.entries(props.preview?.excluded || {}).filter(([, count]) => count)
);
const withMissing = computed(
  () =>
    (props.preview?.sample || []).filter(row => row.missing_variables?.length)
      .length
);
const estimate = computed(() => props.preview?.estimate);
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 rounded-2xl bg-n-alpha-1 border border-n-weak"
    data-testid="audience-preview-panel"
  >
    <div class="flex items-baseline gap-2">
      <span
        class="text-2xl font-semibold text-n-slate-12 tabular-nums"
        data-testid="preview-eligible"
      >
        {{ preview.eligible_count }}
      </span>
      <span class="text-xs text-n-slate-11">
        {{ t('BROADCAST.PREVIEW.ELIGIBLE') }}
      </span>
    </div>

    <ul v-if="excludedEntries.length" class="flex flex-col gap-0.5 m-0 p-0">
      <li
        v-for="[reason, count] in excludedEntries"
        :key="reason"
        class="list-none text-[11px] text-n-amber-11"
      >
        {{
          t(
            `BROADCAST.PREVIEW.EXCLUDED.${reason.toUpperCase()}`,
            { count },
            count
          )
        }}
      </li>
    </ul>

    <p
      v-if="estimate && preview.eligible_count"
      class="m-0 text-[11px] text-n-slate-11"
    >
      {{
        t('BROADCAST.PREVIEW.ESTIMATE', {
          perHour: estimate.per_hour,
          perDay: estimate.per_day,
          days: estimate.days,
          start: estimate.window_start,
          end: estimate.window_end,
        })
      }}
    </p>

    <p v-if="withMissing" class="m-0 text-[11px] text-n-amber-11">
      {{ t('BROADCAST.PREVIEW.MISSING', { count: withMissing }, withMissing) }}
    </p>

    <div v-if="preview.sample?.length" class="flex flex-col gap-2">
      <span class="text-[11px] font-medium text-n-slate-11">
        {{ t('BROADCAST.PREVIEW.SAMPLE', { count: preview.sample.length }) }}
      </span>
      <ul class="flex flex-col gap-2 m-0 p-0 max-h-72 overflow-auto">
        <li
          v-for="row in preview.sample"
          :key="row.contact_id"
          class="list-none flex flex-col gap-1 p-2 rounded-lg bg-n-solid-2"
          :class="row.skip_reason ? 'opacity-60' : ''"
          data-testid="preview-sample-row"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs font-medium text-n-slate-12 truncate">
              {{ row.name || row.phone }}
            </span>
            <span
              v-if="row.skip_reason"
              class="shrink-0 text-[10px] text-n-amber-11"
            >
              {{ t(`BROADCAST.PREVIEW.SKIP.${row.skip_reason.toUpperCase()}`) }}
            </span>
            <span
              v-else-if="row.best_hour !== null && row.best_hour !== undefined"
              class="shrink-0 text-[10px] text-n-teal-11"
            >
              {{ t('BROADCAST.PREVIEW.BEST_HOUR', { hour: row.best_hour }) }}
            </span>
          </div>
          <p class="m-0 text-[11px] text-n-slate-11 whitespace-pre-wrap">
            {{ row.text }}
          </p>
        </li>
      </ul>
    </div>
  </div>
</template>
