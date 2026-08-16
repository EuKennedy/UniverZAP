/**
 * Como um número do painel de IA vira texto na tela, em um lugar só.
 *
 * A faixa no topo de Visão geral e o painel completo da aba mostram os mesmos
 * seis números. Duplicar a formatação garantiria que um dia a faixa arredonda
 * diferente do painel e o operador vê dois valores para a mesma coisa na mesma
 * sessão.
 *
 * Toda função devolve travessão para ausente e nunca zero. "R$ 0,00 por
 * agendamento" lê como se o agente marcasse de graça; "—" lê como ninguém
 * marcou, que é o que significa.
 */

const EMPTY = '—';

const isBlank = value => value === null || value === undefined;

const decimal = new Intl.NumberFormat('pt-BR');
const currency = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

export const formatNumber = value =>
  isBlank(value) ? EMPTY : decimal.format(value);

export const formatBrl = value =>
  isBlank(value) ? EMPTY : currency.format(value);

export const formatBrlFromCents = cents =>
  isBlank(cents) ? EMPTY : currency.format(cents / 100);

export const formatPercent = value => (isBlank(value) ? EMPTY : `${value}%`);

export const formatSeconds = ms =>
  isBlank(ms) ? EMPTY : `${(ms / 1000).toFixed(1)}s`;

// Multiplicador e não porcentagem: "3,2x o que custou" é a frase que um
// operador repete, e porcentagem de um custo é número que ninguém fala.
export const formatRoi = value =>
  isBlank(value) ? EMPTY : `${value.toFixed(2).replace('.', ',')}x`;

// Subir é bom, subir é ruim, ou subir não quer dizer nada. Gasto fica sem cor
// de propósito: gastar mais não é piorar se o agente também trabalhou mais, e
// pintar de vermelho um custo que acompanhou a receita seria mentir com cor.
export const RISING_IS_GOOD = 'good';
export const RISING_IS_BAD = 'bad';
export const RISING_MEANS_NOTHING = 'neutral';

const TONE = {
  good: 'text-n-teal-11',
  bad: 'text-n-ruby-11',
  neutral: 'text-n-slate-11',
};

const arrowFor = change => {
  if (change === 0) return '=';
  return change > 0 ? '↑' : '↓';
};

const toneFor = (direction, change) => {
  if (direction === RISING_MEANS_NOTHING || change === 0) {
    return TONE.neutral;
  }
  const helped =
    change > 0 ? direction === RISING_IS_GOOD : direction === RISING_IS_BAD;
  return helped ? TONE.good : TONE.bad;
};

/**
 * A variação contra a janela anterior, ou null quando não há o que comparar.
 *
 * Null é a primeira vez, não crescimento de 100%: sair de zero não tem
 * porcentagem, e inventar uma seria o painel se elogiando sozinho.
 */
export const buildTrend = (comparison, key, direction) => {
  const change = comparison?.[key]?.change;
  if (isBlank(change)) return null;

  return {
    arrow: arrowFor(change),
    tone: toneFor(direction, change),
    label: `${change > 0 ? '+' : ''}${change.toFixed(1).replace('.', ',')}%`,
  };
};
