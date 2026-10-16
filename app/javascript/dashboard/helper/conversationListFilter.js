// UniverZAP: the conversation list filter — period, agent, labels and kanban,
// nothing else. It is a thin layer over the Chatwoot filter engine: the
// fields become ordinary conditions for POST /conversations/filter.
import { addDays, format, parseISO, subDays } from 'date-fns';

export const LIST_FILTER_PERIODS = {
  TODAY: 'today',
  LAST_7_DAYS: 'last_7_days',
  LAST_30_DAYS: 'last_30_days',
  CUSTOM: 'custom',
};

export const NO_ASSIGNEE = 'none';

export const emptyListFilter = () => ({
  period: '',
  from: '',
  to: '',
  assignee: null,
  labels: [],
  // { id, name, stageIds } — the stages are kept so "the whole funnel" needs
  // no lookup later.
  funnel: null,
  stage: null,
});

// [first, last] local calendar days, both inclusive; either may be missing on
// a custom period.
export const periodRange = ({ period, from, to }, today = new Date()) => {
  switch (period) {
    case LIST_FILTER_PERIODS.TODAY:
      return [today, today];
    case LIST_FILTER_PERIODS.LAST_7_DAYS:
      return [subDays(today, 6), today];
    case LIST_FILTER_PERIODS.LAST_30_DAYS:
      return [subDays(today, 29), today];
    case LIST_FILTER_PERIODS.CUSTOM:
      return [from ? parseISO(from) : null, to ? parseISO(to) : null];
    default:
      return [null, null];
  }
};

const toDay = date => format(date, 'yyyy-MM-dd');

export const listFilterCondition = (attributeKey, filterOperator, values) => ({
  attribute_key: attributeKey,
  filter_operator: filterOperator,
  values,
  query_operator: 'and',
});

// The engine compares calendar days strictly (> and <), so an inclusive
// period goes one day out on each side.
export const buildListFilterConditions = (filter, today = new Date()) => {
  const conditions = [];
  const [first, last] = periodRange(filter, today);
  if (first) {
    conditions.push(
      listFilterCondition('last_activity_at', 'is_greater_than', [
        toDay(subDays(first, 1)),
      ])
    );
  }
  if (last) {
    conditions.push(
      listFilterCondition('last_activity_at', 'is_less_than', [
        toDay(addDays(last, 1)),
      ])
    );
  }
  if (filter.assignee) {
    conditions.push(
      filter.assignee.id === NO_ASSIGNEE
        ? listFilterCondition('assignee_id', 'is_not_present', [])
        : listFilterCondition('assignee_id', 'equal_to', [filter.assignee.id])
    );
  }
  if (filter.labels.length) {
    conditions.push(
      listFilterCondition(
        'labels',
        'equal_to',
        filter.labels.map(label => label.id)
      )
    );
  }
  const stageIds = filter.stage
    ? [filter.stage.id]
    : filter.funnel?.stageIds || [];
  if (stageIds.length) {
    conditions.push(
      listFilterCondition('kanban_stage_id', 'equal_to', stageIds)
    );
  }
  return conditions;
};

const shortDay = day =>
  new Intl.DateTimeFormat(undefined, {
    day: '2-digit',
    month: '2-digit',
  }).format(parseISO(day));

// What the applied filter shows above the list, one chip per choice.
export const describeListFilter = (filter, t) => {
  const chips = [];
  if (filter.period === LIST_FILTER_PERIODS.CUSTOM) {
    const days = [filter.from, filter.to].filter(Boolean).map(shortDay);
    if (days.length) chips.push(days.join(' – '));
  } else if (filter.period) {
    chips.push(t(`FILTER.LIST_FILTER.PERIODS.${filter.period}`));
  }
  if (filter.assignee) chips.push(filter.assignee.name);
  filter.labels.forEach(label => chips.push(label.name));
  if (filter.funnel) {
    chips.push(
      filter.stage
        ? `${filter.funnel.name} › ${filter.stage.name}`
        : filter.funnel.name
    );
  }
  return chips;
};
