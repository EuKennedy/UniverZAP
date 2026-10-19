import {
  customerTypeOf,
  formatAppointment,
  formatPhone,
  fromDateTimeLocal,
  isLidContact,
  originOf,
  stageOf,
  toDateTimeLocal,
} from '../customerSheet';

describe('customerSheet helpers', () => {
  describe('formatPhone', () => {
    it('formats a Brazilian mobile number with country and area code', () => {
      expect(formatPhone('+5531999998888')).toBe('+55 31 99999 8888');
    });

    it('returns the raw value when it is not a phone number', () => {
      expect(formatPhone('abc')).toBe('abc');
      expect(formatPhone('')).toBe('');
    });
  });

  describe('isLidContact', () => {
    it('is true for a WAHA contact that only has a LID', () => {
      expect(
        isLidContact({
          name: '159519548166205@lid',
          identifier: '159519548166205@lid',
        })
      ).toBe(true);
      expect(isLidContact({ name: 'Maria', identifier: '1595@lid' })).toBe(
        true
      );
    });

    it('is false once the contact has a phone number', () => {
      expect(
        isLidContact({ identifier: '1595@lid', phone_number: '+5531999998888' })
      ).toBe(false);
      expect(isLidContact({ name: 'Maria' })).toBe(false);
    });
  });

  describe('originOf', () => {
    it('reads the ad from the conversation attributes', () => {
      const conversation = {
        custom_attributes: {
          origem_lead: 'anuncio_facebook',
          anuncio_id: '120210000003',
          anuncio_titulo: 'Corte masculino sem fila',
          anuncio_url: 'https://fb.me/corte',
        },
      };
      expect(originOf(conversation, {})).toEqual({
        source: 'ad',
        title: 'Corte masculino sem fila',
        url: 'https://fb.me/corte',
      });
    });

    it('treats the lead-anuncio label as an ad and falls back to the ad id', () => {
      const conversation = {
        labels: ['lead-anuncio'],
        custom_attributes: { anuncio_id: '42' },
      };
      expect(originOf(conversation, {}).title).toBe('42');
      expect(originOf({ labels: ['lead-anuncio'] }, {}).source).toBe('ad');
    });

    it('uses the contact first touch when the conversation is not from an ad', () => {
      const contact = {
        custom_attributes: { origem_lead: 'anuncio_facebook' },
      };
      expect(originOf({}, contact)).toEqual({
        source: 'ad',
        title: '',
        url: '',
      });
      expect(
        originOf({}, { custom_attributes: { origem_lead: 'organico' } }).source
      ).toBe('organic');
      expect(originOf({}, {}).source).toBe('organic');
    });
  });

  describe('customerTypeOf', () => {
    const conversation = { id: 10 };

    it('trusts the recorrente attribute when the contact has it', () => {
      expect(
        customerTypeOf({
          contact: { custom_attributes: { recorrente: true } },
          conversation,
        })
      ).toBe('recurring');
      expect(
        customerTypeOf({
          contact: { custom_attributes: { recorrente: false } },
          conversation,
          previousConversations: [{ id: 9, status: 'resolved' }],
        })
      ).toBe('new');
    });

    it('derives recurring from another conversation that already closed', () => {
      expect(
        customerTypeOf({
          conversation,
          previousConversations: [{ id: 9, status: 'resolved' }],
        })
      ).toBe('recurring');
      expect(
        customerTypeOf({
          conversation,
          previousConversations: [
            { id: 9, status: 'open', labels: ['cancelado'] },
          ],
          closingTitles: ['cancelado'],
        })
      ).toBe('recurring');
    });

    it('is new when only the current conversation exists or nothing closed', () => {
      expect(
        customerTypeOf({
          conversation,
          previousConversations: [{ id: 10, status: 'resolved' }],
        })
      ).toBe('new');
      expect(
        customerTypeOf({
          conversation,
          previousConversations: [{ id: 9, status: 'open' }],
        })
      ).toBe('new');
      expect(customerTypeOf({ conversation })).toBe('new');
    });
  });

  describe('stageOf', () => {
    const stages = [
      { title: 'novo-contato', color: '#94A3B8' },
      { title: 'agendado', color: '#14B8A6' },
    ];

    it('finds the stage label among the conversation labels', () => {
      expect(stageOf(['lead-anuncio', 'agendado'], stages)).toEqual(stages[1]);
    });

    it('is null without a stage label', () => {
      expect(stageOf(['lead-anuncio'], stages)).toBeNull();
      expect(stageOf([], [])).toBeNull();
    });
  });

  describe('formatAppointment', () => {
    it('shows weekday, day, month and time in the given locale', () => {
      const text = formatAppointment('2026-10-25T14:00:00.000Z', 'pt_BR');
      expect(text).toContain('25/10');
      expect(text).toContain('14:00');
    });

    it('shows a date-only value as a local day without time', () => {
      const text = formatAppointment('2026-10-25', 'pt_BR');
      expect(text).toContain('25/10');
      expect(text).not.toContain(':');
    });

    it('is empty without a value and keeps junk as is', () => {
      expect(formatAppointment('', 'pt_BR')).toBe('');
      expect(formatAppointment('amanhã', 'pt_BR')).toBe('amanhã');
    });
  });

  describe('datetime-local round trip', () => {
    it('prefills the input and stores ISO 8601', () => {
      const local = toDateTimeLocal('2026-10-25T14:00:00.000Z');
      expect(local).toBe('2026-10-25T14:00');
      expect(fromDateTimeLocal(local)).toBe('2026-10-25T14:00:00.000Z');
      expect(toDateTimeLocal('')).toBe('');
      expect(fromDateTimeLocal('')).toBe('');
    });
  });
});
