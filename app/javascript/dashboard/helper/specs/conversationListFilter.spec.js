import {
  buildListFilterConditions,
  emptyListFilter,
  LIST_FILTER_PERIODS,
  NO_ASSIGNEE,
} from '../conversationListFilter';

const today = new Date(2026, 9, 16);
const build = overrides =>
  buildListFilterConditions({ ...emptyListFilter(), ...overrides }, today);
const brief = conditions =>
  conditions.map(c => [c.attribute_key, c.filter_operator, c.values]);

describe('buildListFilterConditions', () => {
  it('is empty when nothing is chosen', () => {
    expect(build({})).toEqual([]);
  });

  it('turns a period into an inclusive day range for the strict engine', () => {
    expect(brief(build({ period: LIST_FILTER_PERIODS.TODAY }))).toEqual([
      ['last_activity_at', 'is_greater_than', ['2026-10-15']],
      ['last_activity_at', 'is_less_than', ['2026-10-17']],
    ]);
    expect(
      brief(build({ period: LIST_FILTER_PERIODS.LAST_7_DAYS }))[0][2]
    ).toEqual(['2026-10-09']);
  });

  it('keeps an open-ended custom period open', () => {
    expect(
      brief(build({ period: LIST_FILTER_PERIODS.CUSTOM, from: '2026-10-01' }))
    ).toEqual([['last_activity_at', 'is_greater_than', ['2026-09-30']]]);
  });

  it('maps the agent, including nobody', () => {
    expect(brief(build({ assignee: { id: 7, name: 'Taina' } }))).toEqual([
      ['assignee_id', 'equal_to', [7]],
    ]);
    expect(brief(build({ assignee: { id: NO_ASSIGNEE } }))).toEqual([
      ['assignee_id', 'is_not_present', []],
    ]);
  });

  it('sends labels by title and a funnel as all of its stages', () => {
    expect(
      brief(
        build({
          labels: [{ id: 'leads' }, { id: 'retoq' }],
          funnel: { id: 1, stageIds: [10, 11] },
        })
      )
    ).toEqual([
      ['labels', 'equal_to', ['leads', 'retoq']],
      ['kanban_stage_id', 'equal_to', [10, 11]],
    ]);
    expect(
      brief(build({ funnel: { id: 1, stageIds: [10, 11] }, stage: { id: 11 } }))
    ).toEqual([['kanban_stage_id', 'equal_to', [11]]]);
  });
});
