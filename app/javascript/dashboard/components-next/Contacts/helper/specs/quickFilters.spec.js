import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import {
  allConditionsHaveChips,
  quickFilterState,
  withQuickFilter,
} from '../quickFilters';

const now = new Date('2026-10-31T12:00:00Z');

describe('quickFilters', () => {
  it('keeps conditions no chip owns', () => {
    const advanced = {
      attribute_key: 'city',
      filter_operator: 'contains',
      values: 'BH',
      query_operator: 'and',
      attribute_model: 'standard',
    };
    const filters = withQuickFilter([advanced], 'phone', 'without');
    expect(filters.map(item => item.attribute_key)).toEqual([
      'city',
      'phone_number',
    ]);
  });

  it('replaces the condition of the same chip and clears it', () => {
    const first = withQuickFilter([], 'phone', 'with');
    const second = withQuickFilter(first, 'phone', 'without');
    expect(second).toHaveLength(1);
    expect(second[0].filter_operator).toBe('is_not_present');
    expect(withQuickFilter(second, 'phone', null)).toEqual([]);
  });

  it('clears the labels chip when nothing is left selected', () => {
    const filters = withQuickFilter([], 'labels', ['vip']);
    expect(withQuickFilter(filters, 'labels', [])).toEqual([]);
  });

  it('reads every chip back from the conditions', () => {
    let filters = withQuickFilter([], 'labels', ['vip', 'lead']);
    filters = withQuickFilter(filters, 'origin', 'organico');
    filters = withQuickFilter(filters, 'type', 'new');
    filters = withQuickFilter(filters, 'period', 30, now);
    filters = withQuickFilter(filters, 'phone', 'with');

    const state = quickFilterState(filters, now);
    expect(state.labels.map(item => item.id)).toEqual(['vip', 'lead']);
    expect(state.origin).toBe('organico');
    expect(state.type).toBe('new');
    expect(state.period).toBe(30);
    expect(state.phone).toBe('with');
  });

  it('leaves the period chip empty for a date picked in the dialog', () => {
    const filters = [
      {
        attribute_key: 'created_at',
        filter_operator: 'is_greater_than',
        values: '2026-10-20',
      },
    ];
    expect(quickFilterState(filters, now).period).toBeUndefined();
  });

  it('knows when a condition has no chip to show it', () => {
    const chips = withQuickFilter([], 'phone', 'with');
    expect(allConditionsHaveChips(chips, now)).toBe(true);
    expect(
      allConditionsHaveChips(
        [
          ...chips,
          {
            attribute_key: 'phone_number',
            filter_operator: 'contains',
            values: '31',
          },
        ],
        now
      )
    ).toBe(false);
  });

  it('turns into the payload the filter endpoint expects', () => {
    let filters = withQuickFilter([], 'labels', ['vip']);
    filters = withQuickFilter(filters, 'type', 'recurring');
    filters = withQuickFilter(filters, 'phone', 'without');

    const { payload } = filterQueryGenerator(filters);
    expect(payload[0].values).toEqual(['vip']);
    expect(payload[1].values).toEqual([true]);
    expect(payload[2].values).toEqual([]);
    expect(payload[2].query_operator).toBeUndefined();
  });
});
