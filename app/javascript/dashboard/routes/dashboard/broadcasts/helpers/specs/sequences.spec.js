import { describeOffset, offsetToStep, stepToOffset } from '../sequences';

describe('sequences helpers', () => {
  it('converte "1 dia antes" em minutos negativos e volta', () => {
    const payload = stepToOffset({
      amount: 1,
      unit: 'days',
      direction: 'before',
      text: ' Lembrete ',
      cancelIfReply: false,
    });

    expect(payload).toEqual({
      offset_minutes: -1440,
      text: 'Lembrete',
      cancel_if_reply: false,
    });
    expect(offsetToStep(payload)).toEqual({
      amount: 1,
      unit: 'days',
      direction: 'before',
      text: 'Lembrete',
      cancelIfReply: false,
    });
  });

  it('usa horas quando não é dia cheio', () => {
    expect(offsetToStep({ offset_minutes: 180, text: 'x' })).toMatchObject({
      amount: 3,
      unit: 'hours',
      direction: 'after',
      cancelIfReply: true,
    });
  });

  it('descreve o passo com a chave de i18n certa', () => {
    const t = vi.fn((key, values) => `${key}:${values.count}`);

    expect(describeOffset({ offset_minutes: 2880 }, t)).toBe(
      'BROADCAST.SEQUENCES.OFFSET.DAYS_AFTER:2'
    );
  });
});
