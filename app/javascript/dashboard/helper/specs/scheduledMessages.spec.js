import {
  buildShortcuts,
  firstNameOf,
  fromDateTimeLocal,
  missingVariables,
  previewText,
  sortScheduled,
  toDateTimeLocal,
} from '../scheduledMessages';

describe('scheduledMessages helpers', () => {
  describe('buildShortcuts', () => {
    // Terça, 20/10/2026, 10:00 no fuso local.
    const tuesday = new Date(2026, 9, 20, 10, 0);

    it('oferece hoje 18h de manhã, amanhã 9h, daqui 3 dias e segunda de manhã', () => {
      const byKey = Object.fromEntries(
        buildShortcuts(tuesday).map(item => [item.key, item.at])
      );

      expect(byKey.IN_1_HOUR).toEqual(new Date(2026, 9, 20, 11, 0));
      expect(byKey.TODAY_18).toEqual(new Date(2026, 9, 20, 18, 0));
      expect(byKey.TOMORROW_9).toEqual(new Date(2026, 9, 21, 9, 0));
      expect(byKey.IN_3_DAYS).toEqual(new Date(2026, 9, 23, 10, 0));
      expect(byKey.MONDAY_MORNING).toEqual(new Date(2026, 9, 26, 9, 0));
    });

    it('não oferece hoje 18h no fim da tarde e segunda vira a próxima numa segunda', () => {
      const mondayEvening = new Date(2026, 9, 26, 17, 30);
      const keys = buildShortcuts(mondayEvening).map(item => item.key);

      expect(keys).not.toContain('TODAY_18');
      expect(
        buildShortcuts(mondayEvening).find(i => i.key === 'MONDAY_MORNING').at
      ).toEqual(new Date(2026, 10, 2, 9, 0));
    });

    it('acrescenta o melhor horário quando o backend sugere', () => {
      const best = new Date(2026, 9, 20, 14, 0).toISOString();
      const last = buildShortcuts(tuesday, best).at(-1);

      expect(last).toMatchObject({ key: 'BEST_TIME', best: true });
      expect(last.at.toISOString()).toBe(best);
    });
  });

  it('converte o datetime-local ida e volta', () => {
    const iso = new Date(2026, 9, 21, 9, 0).toISOString();

    expect(toDateTimeLocal(iso)).toBe('2026-10-21T09:00');
    expect(fromDateTimeLocal('2026-10-21T09:00')).toBe(iso);
    expect(toDateTimeLocal(null)).toBe('');
  });

  it('primeiro nome ignora telefone e e-mail', () => {
    expect(firstNameOf('mariana souza')).toBe('Mariana');
    expect(firstNameOf('~ Bia')).toBe('Bia');
    expect(firstNameOf('+55 31 99999-0000')).toBe('');
    expect(firstNameOf('ana@x.com')).toBe('');
  });

  it('a prévia preenche variáveis e escolhe a primeira opção do spintax', () => {
    const context = {
      contact: { name: 'Carla Dias' },
      conversation: { custom_attributes: { servico: 'Escova' } },
    };

    expect(
      previewText('{Oi|Olá} {primeiro_nome}, sua {servico}? {outra}', context)
    ).toBe('Oi Carla, sua Escova? {outra}');
    expect(
      missingVariables('{primeiro_nome} {profissional} {servico}', context)
    ).toEqual(['profissional']);
  });

  it('ordena pendentes primeiro, por horário', () => {
    const list = sortScheduled([
      { id: 1, status: 'sent', send_at: '2026-10-19T10:00:00Z' },
      { id: 2, status: 'scheduled', send_at: '2026-10-22T10:00:00Z' },
      { id: 3, status: 'scheduled', send_at: '2026-10-21T10:00:00Z' },
    ]);

    expect(list.map(item => item.id)).toEqual([3, 2, 1]);
  });
});
