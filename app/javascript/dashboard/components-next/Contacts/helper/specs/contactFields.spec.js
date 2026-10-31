import {
  contactLocation,
  contactOrigin,
  contactPhone,
  contactTitle,
  contactType,
  customFields,
  formatRelative,
  hasRawName,
} from '../contactFields';

describe('contactFields', () => {
  describe('contactTitle', () => {
    it('keeps a real name', () => {
      expect(contactTitle({ name: 'Neyla Tereza Flores' })).toBe(
        'Neyla Tereza Flores'
      );
    });

    it('shows the phone when the name is a c.us handle', () => {
      expect(
        contactTitle({
          name: '553398300240@c.us',
          phoneNumber: '+5533998300240',
        })
      ).toBe('+55 33 99830 0240');
    });

    it('reads the number out of the handle when the phone is empty', () => {
      expect(contactTitle({ name: '5531984956383@c.us' })).toBe(
        '+55 31 98495 6383'
      );
    });

    it('has nothing readable for a bare lid', () => {
      expect(contactTitle({ name: '70171343482916@lid' })).toBeNull();
    });
  });

  it('treats handles and digits as raw names', () => {
    expect(hasRawName({ name: '70171343482916@lid' })).toBe(true);
    expect(hasRawName({ name: '5531984956383' })).toBe(true);
    expect(hasRawName({ name: '' })).toBe(true);
    expect(hasRawName({ name: 'Carol' })).toBe(false);
  });

  it('formats the phone from the identifier as a last resort', () => {
    expect(contactPhone({ identifier: '5531984956383@s.whatsapp.net' })).toBe(
      '+55 31 98495 6383'
    );
    expect(contactPhone({ identifier: '70171343482916@lid' })).toBe('');
  });

  it('reads type and origin from the custom attributes', () => {
    expect(contactType({ customAttributes: { recorrente: true } })).toBe(
      'recurring'
    );
    expect(contactType({ customAttributes: {} })).toBe('new');
    expect(
      contactOrigin({ customAttributes: { origem_lead: 'anuncio_facebook' } })
    ).toBe('ad');
    expect(
      contactOrigin({ customAttributes: { origem_lead: 'organico' } })
    ).toBe('organic');
    expect(contactOrigin({ customAttributes: {} })).toBeNull();
  });

  it('joins city and country', () => {
    expect(
      contactLocation({
        additionalAttributes: { city: 'Belo Horizonte', countryCode: 'BR' },
      })
    ).toBe('Belo Horizonte, Brazil');
    expect(contactLocation({})).toBe('');
  });

  it('leaves out the attributes that have their own column', () => {
    const fields = customFields([
      {
        attributeKey: 'recorrente',
        attributeDisplayName: 'Recorrente',
        attributeDisplayType: 'checkbox',
      },
      {
        attributeKey: 'aniversario',
        attributeDisplayName: 'Aniversário',
        attributeDisplayType: 'date',
      },
    ]);
    expect(fields.map(field => field.attributeKey)).toEqual(['aniversario']);
  });

  it('describes last activity relative to now', () => {
    const now = new Date('2026-10-31T12:00:00Z').getTime();
    const threeDaysAgo = now / 1000 - 3 * 86400;
    expect(formatRelative(threeDaysAgo, 'en', now)).toBe('3 days ago');
    expect(formatRelative(null, 'en', now)).toBe('');
  });
});
