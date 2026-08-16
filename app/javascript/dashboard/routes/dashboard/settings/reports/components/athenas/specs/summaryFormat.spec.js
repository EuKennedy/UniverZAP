import {
  formatNumber,
  formatBrl,
  formatBrlFromCents,
  formatPercent,
  formatSeconds,
  formatRoi,
  buildTrend,
  RISING_IS_GOOD,
  RISING_IS_BAD,
  RISING_MEANS_NOTHING,
} from '../summaryFormat';

// O Intl usa espaço não separável entre "R$" e o número. Comparar contra um
// espaço comum falharia por um caractere invisível, que é o tipo de teste que
// some uma tarde inteira de alguém.
const plain = value => value.replace(/\u00A0/g, ' ');

const EMPTY = '—';

describe('summaryFormat', () => {
  // O painel inteiro se apoia nisto: ausente é travessão, nunca zero. "R$ 0,00
  // por agendamento" lê como se o agente marcasse de graça, quando significa
  // que ninguém marcou.
  describe('ausente contra zero', () => {
    it.each([
      ['formatNumber', formatNumber],
      ['formatBrl', formatBrl],
      ['formatBrlFromCents', formatBrlFromCents],
      ['formatPercent', formatPercent],
      ['formatSeconds', formatSeconds],
      ['formatRoi', formatRoi],
    ])('%s devolve travessao para null e undefined', (_name, format) => {
      expect(format(null)).toBe(EMPTY);
      expect(format(undefined)).toBe(EMPTY);
    });

    it('formata zero como zero e nao como ausente', () => {
      expect(formatNumber(0)).toBe('0');
      expect(plain(formatBrl(0))).toBe('R$ 0,00');
      expect(formatPercent(0)).toBe('0%');
    });
  });

  describe('numeros', () => {
    it('agrupa milhar no padrao brasileiro', () => {
      expect(formatNumber(1240)).toBe('1.240');
      expect(formatNumber(1234567)).toBe('1.234.567');
    });

    it('converte centavos em reais', () => {
      expect(plain(formatBrlFromCents(9900))).toBe('R$ 99,00');
      expect(plain(formatBrlFromCents(5))).toBe('R$ 0,05');
    });

    it('mostra latencia em segundos com uma casa', () => {
      expect(formatSeconds(1500)).toBe('1.5s');
      expect(formatSeconds(340)).toBe('0.3s');
    });

    // Multiplicador e não porcentagem: "3,20x o que custou" é a frase que um
    // operador repete, e porcentagem de um custo é número que ninguém fala.
    it('mostra retorno como multiplicador com virgula', () => {
      expect(formatRoi(3.2)).toBe('3,20x');
      expect(formatRoi(0.5)).toBe('0,50x');
    });
  });

  describe('a variacao contra o periodo anterior', () => {
    const comparison = {
      subiu: { previous: 100, change: 24 },
      caiu: { previous: 100, change: -19.7 },
      parado: { previous: 100, change: 0 },
      estreando: { previous: 0, change: null },
    };

    // Sair de zero não é crescimento de 100%, é a primeira vez. Inventar uma
    // porcentagem aqui seria o painel se elogiando sozinho.
    it('nao inventa variacao quando nao ha base para comparar', () => {
      expect(buildTrend(comparison, 'estreando', RISING_IS_GOOD)).toBeNull();
      expect(buildTrend(comparison, 'inexistente', RISING_IS_GOOD)).toBeNull();
      expect(buildTrend(undefined, 'subiu', RISING_IS_GOOD)).toBeNull();
    });

    it('marca o sinal e a seta pela direcao do movimento', () => {
      expect(buildTrend(comparison, 'subiu', RISING_IS_GOOD)).toMatchObject({
        arrow: '↑',
        label: '+24,0%',
      });
      expect(buildTrend(comparison, 'caiu', RISING_IS_GOOD)).toMatchObject({
        arrow: '↓',
        label: '-19,7%',
      });
      expect(buildTrend(comparison, 'parado', RISING_IS_GOOD).arrow).toBe('=');
    });

    it('pinta de verde quando subir e a intencao', () => {
      expect(buildTrend(comparison, 'subiu', RISING_IS_GOOD).tone).toBe(
        'text-n-teal-11'
      );
      expect(buildTrend(comparison, 'caiu', RISING_IS_GOOD).tone).toBe(
        'text-n-ruby-11'
      );
    });

    // Marcadas para revisão subindo é piora, e o mesmo +24% que é verde em
    // respostas tem que sair vermelho aqui.
    it('inverte a cor quando subir e a piora', () => {
      expect(buildTrend(comparison, 'subiu', RISING_IS_BAD).tone).toBe(
        'text-n-ruby-11'
      );
      expect(buildTrend(comparison, 'caiu', RISING_IS_BAD).tone).toBe(
        'text-n-teal-11'
      );
    });

    // Gastar mais não é piorar se o agente também trabalhou mais. Pintar de
    // vermelho um custo que acompanhou a receita seria mentir com cor.
    it('deixa o custo sem cor nos dois sentidos', () => {
      expect(buildTrend(comparison, 'subiu', RISING_MEANS_NOTHING).tone).toBe(
        'text-n-slate-11'
      );
      expect(buildTrend(comparison, 'caiu', RISING_MEANS_NOTHING).tone).toBe(
        'text-n-slate-11'
      );
    });

    it('deixa sem cor quando nao houve movimento nenhum', () => {
      expect(buildTrend(comparison, 'parado', RISING_IS_GOOD).tone).toBe(
        'text-n-slate-11'
      );
    });
  });
});
