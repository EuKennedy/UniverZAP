import { toRichParts } from '../richText';

describe('toRichParts', () => {
  it('deixa texto sem marcação inteiro', () => {
    expect(toRichParts('vá em Configurações')).toEqual([
      { text: 'vá em Configurações', bold: false },
    ]);
  });

  it('transforma **isto** em um pedaço em negrito', () => {
    expect(toRichParts('vá em **Configurações** agora')).toEqual([
      { text: 'vá em ', bold: false },
      { text: 'Configurações', bold: true },
      { text: ' agora', bold: false },
    ]);
  });

  it('entende vários negritos na mesma resposta', () => {
    expect(toRichParts('**um** e **dois**').filter(p => p.bold)).toEqual([
      { text: 'um', bold: true },
      { text: 'dois', bold: true },
    ]);
  });

  it('atravessa quebra de linha, que é onde o modelo mais usa', () => {
    expect(toRichParts('**Passo 1\nPasso 2**')[0].bold).toBe(true);
  });

  // Asterisco solto é asterisco, não começo de negrito eterno.
  it('não come o resto do texto quando o par não fecha', () => {
    expect(toRichParts('isto ** não fecha')).toEqual([
      { text: 'isto ** não fecha', bold: false },
    ]);
  });

  it('não inventa pedaço para resposta vazia', () => {
    expect(toRichParts('')).toEqual([{ text: '', bold: false }]);
    expect(toRichParts(null)).toEqual([{ text: '', bold: false }]);
  });

  // O texto vem do modelo, e modelo repete o que leu.
  it('trata marcação como texto, nunca como HTML', () => {
    expect(toRichParts('<script>alert(1)</script>')).toEqual([
      { text: '<script>alert(1)</script>', bold: false },
    ]);
  });
});
