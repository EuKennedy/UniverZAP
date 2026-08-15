<script setup>
/**
 * One row per agent, every column meaning exactly what the same column means in
 * the summary above it.
 *
 * This is the reason an account panel exists at all. The per-agent screens each
 * answer "how is this one doing"; only a table answers "which of them is worth
 * the money", and that question is the whole point of running more than one.
 *
 * Sortable, because the question changes: today it is which one costs most,
 * next week which one is being corrected most.
 */
import { computed, h } from 'vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getSortedRowModel,
} from '@tanstack/vue-table';
import { useI18n } from 'vue-i18n';
import Table from 'dashboard/components/table/Table.vue';

const props = defineProps({
  agents: { type: Array, default: () => [] },
});

const { t } = useI18n();

const header = key => t(`ATHENAS_REPORT.TABLE.${key}`);

const decimal = new Intl.NumberFormat('pt-BR');
const money = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

// tabular-nums HERE and not on the stat tiles: these digits stack in a column
// and have to line up, which is the one place equal-width figures earn their
// looseness.
const cell = (text, muted = false) =>
  h(
    'span',
    {
      class: muted
        ? 'tabular-nums text-n-slate-11'
        : 'tabular-nums text-n-slate-12',
    },
    text
  );

const blank = () => cell('—', true);

const columnHelper = createColumnHelper();

const nameColumn = columnHelper.accessor('name', {
  header: header('AGENT'),
  size: 200,
  cell: cellProps =>
    h('div', { class: 'flex gap-2 items-center min-w-0' }, [
      h(
        'span',
        { class: 'truncate text-n-slate-12' },
        cellProps.row.original.name
      ),
      cellProps.row.original.active
        ? null
        : h(
            'span',
            {
              class:
                'flex-shrink-0 px-1.5 text-[11px] rounded-full text-n-slate-11 bg-n-alpha-1',
            },
            t('ATHENAS_REPORT.TABLE.PAUSED')
          ),
    ]),
});

const numberColumn = (key, labelKey, format, muted = false) =>
  columnHelper.accessor(key, {
    header: header(labelKey),
    size: 110,
    cell: cellProps => {
      const value = cellProps.getValue();
      if (value === null || value === undefined) return blank();
      return cell(format(value), muted);
    },
  });

const columns = [
  nameColumn,
  numberColumn('replies', 'REPLIES', value => decimal.format(value)),
  numberColumn('cost_cents_brl', 'COST', value => money.format(value / 100)),
  numberColumn('cost_per_reply_brl', 'COST_PER_REPLY', value =>
    money.format(value)
  ),
  numberColumn(
    'p95_latency_ms',
    'P95',
    value => `${(value / 1000).toFixed(1)}s`
  ),
  numberColumn('success_rate', 'RELIABILITY', value => `${value}%`),
  numberColumn('flagged', 'FLAGGED', value => decimal.format(value), true),
  numberColumn('revenue_brl', 'REVENUE', value => money.format(value)),
  // Both agendas count here now. A belezaki agent used to show an em dash,
  // because the salon holds the book and the confirmation was being dropped;
  // Ai::Belezaki::BookingRecorder writes it down, so the column is a number for
  // every agent again.
  numberColumn('bookings', 'BOOKINGS', value => decimal.format(value)),
  numberColumn('roi', 'ROI', value => `${value.toFixed(2).replace('.', ',')}x`),
];

const table = useVueTable({
  get data() {
    return props.agents;
  },
  columns,
  enableSorting: true,
  getCoreRowModel: getCoreRowModel(),
  getSortedRowModel: getSortedRowModel(),
});

const isEmpty = computed(() => props.agents.length === 0);
</script>

<template>
  <div class="flex flex-col gap-2">
    <h4 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('ATHENAS_REPORT.TABLE.TITLE') }}
    </h4>
    <p v-if="isEmpty" class="m-0 text-sm text-n-slate-11">
      {{ t('ATHENAS_REPORT.TABLE.EMPTY') }}
    </p>
    <!-- The table scrolls inside its own box. A report screen that scrolls
      sideways as a whole loses the axis of every chart above it. -->
    <div v-else class="overflow-x-auto">
      <Table :table="table" class="min-w-[52rem]" />
    </div>
  </div>
</template>
